#!/usr/bin/env python3
"""Fail-closed OOXML parser for five planned Census inventory profiles.

The parser emits only present-day schema diagnostics or unauthenticated local
future-capture candidates.  It never authenticates Census, admits an origin,
or authorizes model use.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import posixpath
import stat
import sys
import tomllib
import zipfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path, PurePosixPath
from types import MappingProxyType
from typing import Any, Iterable, Mapping, Sequence
from urllib.parse import urlsplit
from xml.etree import ElementTree as ET

sys.dont_write_bytecode = True

SCHEMA_VERSION = "beforeit-us-census-inventory-release-diagnostic.v1"
GENERATOR_VERSION = "beforeit-us-census-inventory-ooxml-parser.v1"
PROFILE_SCHEMA_VERSION = "beforeit-us-census-inventory-release-profile.v1"
BINDING_SCHEMA_VERSION = "beforeit-us-census-inventory-local-binding.v1"
STATUS = "CANNOT_RUN"
ROLE = "PRESENT_DAY_SCHEMA_DIAGNOSTIC_NONADMITTING"
CANONICALIZATION = "utf8-sorted-keys-compact-json-lf.v1"
MODULE_PATH = Path(os.path.abspath(__file__))
PROFILE_PATH = MODULE_PATH.with_name("census_inventory_release_profile_v1.json")
CONTRACT_PATH = (
    MODULE_PATH.parent.parent.parent
    / "prospective"
    / "prospective_2026q3_contract_v2.toml"
)
EXPECTED_PROFILE_PHYSICAL_SHA256 = (
    "b0a422598a4a59856268c63c8f6f707865dd093f6953db5d2253a6570200c463"
)
EXPECTED_CONTRACT_PHYSICAL_SHA256 = (
    "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"
)
EXPECTED_PROFILE_IDS = (
    "m3_2026_08_stage_table",
    "mwts_2026_08_adjusted_inventory",
    "mwts_2026_08_not_adjusted_inventory",
    "mrts_2026_08_inventory",
    "m3_2026_09_advance_total",
)
_EXPECTED_BINDINGS_BUILD = {
    "m3_2026_08_stage_table": {
        "requirement_id": "census_m3_inventory_stages",
        "event_id": "census_m3_2026_08_full",
        "reference_period": "2026-08",
        "scheduled_timestamp_utc": "2026-10-02T14:00:00Z",
        "capture_deadline_utc": "2026-10-02T14:15:00Z",
        "source_url": (
            "https://www.census.gov/manufacturing/m3/prel/table6p.xlsx"
        ),
        "selector": (
            "CENSUS:M3:ReferencePeriod=2026-08:full_report:Table=6:"
            "inventories_by_stage_of_fabrication:materials_and_supplies,"
            "work_in_process,finished_goods,total:"
            "SA_and_valuation_metadata_required=true"
        ),
        "parser_kind": "m3_full_table6",
    },
    "mwts_2026_08_adjusted_inventory": {
        "requirement_id": "census_mwts_inventory_stock",
        "event_id": "census_mwts_2026_08",
        "reference_period": "2026-08",
        "scheduled_timestamp_utc": "2026-10-08T14:00:00Z",
        "capture_deadline_utc": "2026-10-08T14:15:00Z",
        "source_url": (
            "https://www.census.gov/wholesale/xls/mwts/timeseries1.xlsx"
        ),
        "selector": (
            "CENSUS:MWTS:ReferencePeriod=2026-08:member=timeseries1.xlsx:"
            "Geography=US:stock_time=end_of_month:"
            "published_unit=millions_current_dollars:"
            "valuation=not_adjusted_for_price_changes:adjustment_state="
            "seasonally_and_trading_day_adjusted:merchant_wholesalers_"
            "excluding_manufacturers_sales_branches_and_offices=true:"
            "full_published_kind_of_business_rows=true:"
            "inventory_and_inventory_sales_ratio=true"
        ),
        "parser_kind": "mwts_adjusted",
    },
    "mwts_2026_08_not_adjusted_inventory": {
        "requirement_id": "census_mwts_inventory_stock",
        "event_id": "census_mwts_2026_08",
        "reference_period": "2026-08",
        "scheduled_timestamp_utc": "2026-10-08T14:00:00Z",
        "capture_deadline_utc": "2026-10-08T14:15:00Z",
        "source_url": (
            "https://www.census.gov/wholesale/xls/mwts/timeseries2.xlsx"
        ),
        "selector": (
            "CENSUS:MWTS:ReferencePeriod=2026-08:member=timeseries2.xlsx:"
            "Geography=US:stock_time=end_of_month:"
            "published_unit=millions_current_dollars:"
            "valuation=not_adjusted_for_price_changes:adjustment_state="
            "not_adjusted:merchant_wholesalers_excluding_manufacturers_"
            "sales_branches_and_offices=true:"
            "full_published_kind_of_business_rows=true:"
            "inventory_and_inventory_sales_ratio=true"
        ),
        "parser_kind": "mwts_not_adjusted",
    },
    "mrts_2026_08_inventory": {
        "requirement_id": "census_mrts_inventory_stock",
        "event_id": "census_mrts_inventory_2026_08",
        "reference_period": "2026-08",
        "scheduled_timestamp_utc": "2026-10-15T14:00:00Z",
        "capture_deadline_utc": "2026-10-15T14:15:00Z",
        "source_url": (
            "https://www.census.gov/retail/mrtsinv/www/"
            "mrtsinv92-present.xlsx"
        ),
        "selector": (
            "CENSUS:MRTS:ReferencePeriod=2026-08:"
            "member=mrtsinv92-present.xlsx:Geography=US:"
            "stock_time=end_of_month:published_unit=millions_current_dollars:"
            "valuation=not_adjusted_for_price_changes:"
            "adjustment_states=SA,NSA:"
            "full_published_kind_of_business_rows=true:"
            "inventory_and_inventory_sales_ratio=true"
        ),
        "parser_kind": "mrts",
    },
    "m3_2026_09_advance_total": {
        "requirement_id": "census_m3_inventory_stages",
        "event_id": "census_m3_2026_09_advance",
        "reference_period": "2026-09",
        "scheduled_timestamp_utc": "2026-10-27T12:30:00Z",
        "capture_deadline_utc": "2026-10-27T12:45:00Z",
        "source_url": (
            "https://www.census.gov/manufacturing/m3/adv/tabletm.xlsx"
        ),
        "selector": (
            "CENSUS:M3:ReferencePeriod=2026-09:advance_report:"
            "total_manufacturing_inventories:"
            "SA_and_valuation_metadata_required=true"
        ),
        "parser_kind": "m3_advance_total",
    },
}
EXPECTED_BINDINGS = MappingProxyType(
    {
        key: MappingProxyType(dict(value))
        for key, value in _EXPECTED_BINDINGS_BUILD.items()
    }
)
del _EXPECTED_BINDINGS_BUILD
HARD_FALSE_GATES = (
    "origin_admissible",
    "provider_provenance_verified",
    "transport_authenticated",
    "custody_verified",
    "availability_policy_verified",
    "qualified_dispatch_allowed",
    "model_input_allowed",
    "forecast_execution_allowed",
    "truth_access_allowed",
    "scoring_allowed",
    "accuracy_claim_allowed",
    "promotion_allowed",
    "production_allowed",
    "inventory_mutation_authorized",
    "ready",
)
M3_FULL_ROW_IDS = (
    "all_manufacturing",
    "durable_goods",
    "wood_products",
    "nonmetallic_mineral_products",
    "primary_metals",
    "fabricated_metal_products",
    "machinery",
    "computers_and_electronic_products",
    "electrical_equipment_appliances_and_components_continuation",
    "electrical_equipment_appliances_and_components",
    "transportation_equipment",
    "furniture_and_related_products",
    "miscellaneous_products",
    "nondurable_goods",
    "food_products",
    "beverage_and_tobacco_products",
    "textiles",
    "textile_products",
    "apparel",
    "leather_and_allied_products",
    "paper_products",
    "printing",
    "petroleum_and_coal_products",
    "chemical_products",
    "plastics_and_rubber_products",
)
M3_FULL_LABEL_ROWS = (
    15,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
    41,
)
M3_FULL_DATA_INDEXES = tuple(index for index in range(25) if index != 8)
M3_ADVANCE_ROW_IDS = (
    "all_manufacturing",
    "durable_goods",
    "nondurable_goods",
    "food_products",
    "beverage_and_tobacco_products",
    "textile_mills",
    "textile_products",
    "apparel",
    "leather_and_allied_products",
    "paper_products",
    "printing",
    "petroleum_and_coal_products",
    "chemical_products",
    "plastics_and_rubber_products",
)
M3_ADVANCE_ROWS = tuple(range(54, 81, 2))
MRTS_ROW_IDS = (
    "retail_total",
    "retail_excluding_motor_vehicle_and_parts_dealers",
    "motor_vehicle_and_parts_dealers",
    "furniture_home_furnishings_electronics_and_appliance_stores",
    "building_materials_garden_equipment_and_supplies_dealers",
    "food_and_beverage_stores",
    "clothing_and_clothing_accessories_stores",
    "general_merchandise_stores",
    "department_stores",
)
MWTS_ROW_IDS = (
    "total_merchant_wholesalers_excluding_manufacturers_sales_branches",
    "durable_goods",
    "motor_vehicle_and_parts_and_supplies",
    "furniture_and_home_furnishings",
    "lumber_and_other_construction_materials",
    "professional_and_commercial_equipment_and_supplies",
    "computer_peripheral_equipment_and_software",
    "metals_and_minerals_except_petroleum",
    "household_appliances_and_electrical_and_electronic_goods",
    "hardware_plumbing_heating_equipment_and_supplies",
    "machinery_equipment_and_supplies",
    "miscellaneous_durable_goods",
    "nondurable_goods",
    "paper_and_paper_products",
    "drugs_and_druggists_sundries",
    "apparel_piece_goods_and_notions",
    "grocery_and_related_products",
    "farm_product_raw_materials",
    "chemicals_and_allied_products",
    "petroleum_and_petroleum_products",
    "beer_wine_and_distilled_alcoholic_beverages",
    "miscellaneous_nondurable_goods",
)
MONTHS = (
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
)
M3_MONTHS_FULL = (
    "Jan.",
    "Feb.",
    "Mar.",
    "Apr.",
    "May",
    "June",
    "July",
    "Aug.",
    "Sept.",
    "Oct.",
    "Nov.",
    "Dec.",
)
M3_MONTHS_ADVANCE = (
    "Jan.",
    "Feb.",
    "Mar.",
    "Apr.",
    "May",
    "Jun.",
    "Jul.",
    "Aug.",
    "Sep.",
    "Oct.",
    "Nov.",
    "Dec.",
)
MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
DOC_REL_NS = (
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
)
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
CONTENT_TYPES_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
MAIN = "{" + MAIN_NS + "}"
DOC_REL = "{" + DOC_REL_NS + "}"
PKG_REL = "{" + PKG_REL_NS + "}"
CONTENT_TYPES = "{" + CONTENT_TYPES_NS + "}"
MAX_RAW_BYTES = 16_000_000
MAX_ZIP_MEMBERS = 256
MAX_MEMBER_BYTES = 12_000_000
MAX_TOTAL_UNCOMPRESSED_BYTES = 64_000_000
MAX_COMPRESSION_RATIO = 200
FORBIDDEN_MEMBER_TOKENS = (
    "vbaproject",
    "activex",
    "embeddings/",
    "oleobjects/",
    "externallinks/",
    "connections",
    "customxml/",
)
FORBIDDEN_RELATION_TOKENS = (
    "externallink",
    "hyperlink",
    "oleobject",
    "vba",
)
ALLOWED_RELATION_TYPES = (
    DOC_REL_NS + "/officeDocument",
    DOC_REL_NS + "/extended-properties",
    PKG_REL_NS + "/metadata/core-properties",
    DOC_REL_NS + "/custom-properties",
    DOC_REL_NS + "/worksheet",
    DOC_REL_NS + "/sharedStrings",
    DOC_REL_NS + "/styles",
    DOC_REL_NS + "/theme",
    DOC_REL_NS + "/printerSettings",
)
WORKBOOK_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"
)
RELATIONSHIPS_CONTENT_TYPE = (
    "application/vnd.openxmlformats-package.relationships+xml"
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
THEME_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.theme+xml"
)
EXTENDED_PROPERTIES_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.extended-properties+xml"
)
CORE_PROPERTIES_CONTENT_TYPE = (
    "application/vnd.openxmlformats-package.core-properties+xml"
)
CUSTOM_PROPERTIES_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.custom-properties+xml"
)
PRINTER_SETTINGS_CONTENT_TYPE = (
    "application/vnd.openxmlformats-officedocument.spreadsheetml.printerSettings"
)
RELATION_CONTENT_TYPE_RULES = (
    (DOC_REL_NS + "/officeDocument", WORKBOOK_CONTENT_TYPE),
    (DOC_REL_NS + "/extended-properties", EXTENDED_PROPERTIES_CONTENT_TYPE),
    (PKG_REL_NS + "/metadata/core-properties", CORE_PROPERTIES_CONTENT_TYPE),
    (DOC_REL_NS + "/custom-properties", CUSTOM_PROPERTIES_CONTENT_TYPE),
    (DOC_REL_NS + "/worksheet", WORKSHEET_CONTENT_TYPE),
    (DOC_REL_NS + "/sharedStrings", SHARED_STRINGS_CONTENT_TYPE),
    (DOC_REL_NS + "/styles", STYLES_CONTENT_TYPE),
    (DOC_REL_NS + "/theme", THEME_CONTENT_TYPE),
    (DOC_REL_NS + "/printerSettings", PRINTER_SETTINGS_CONTENT_TYPE),
)


class ProfileError(RuntimeError):
    """Raised when source bytes, schema, or replay evidence fails closed."""


@dataclass(frozen=True)
class Cell:
    reference: str
    row: int
    column: int
    cell_type: str
    style_index: int
    value: str | None
    raw_value: str | None


@dataclass(frozen=True)
class Sheet:
    name: str
    part_name: str
    dimension: str | None
    cells: Mapping[tuple[int, int], Cell]
    xml_sha256: str


@dataclass(frozen=True)
class Workbook:
    raw_sha256: str
    raw_byte_count: int
    zip_member_count: int
    zip_member_manifest_sha256: str
    content_types_manifest_sha256: str
    relationship_manifest_sha256: str
    shared_strings_semantic_sha256: str
    styles_semantic_sha256: str
    sheet_names: tuple[str, ...]
    sheets: Mapping[str, Sheet]


def fail(message: str) -> None:
    raise ProfileError(message)


def _is_ascii_digits(value: str) -> bool:
    return bool(value) and all("0" <= character <= "9" for character in value)


def _is_sha256_text(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _is_uint_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value) and (
        value == "0"
        or (
            value[0] in "123456789"
            and (len(value) == 1 or _is_ascii_digits(value[1:]))
        )
    )


def _is_positive_int_text(value: Any) -> bool:
    return (
        isinstance(value, str)
        and bool(value)
        and value[0] in "123456789"
        and (len(value) == 1 or _is_ascii_digits(value[1:]))
    )


def _is_decimal_text(value: Any, *, nonnegative: bool = False) -> bool:
    if not isinstance(value, str) or not value:
        return False
    body = value
    if body.startswith("-"):
        if nonnegative:
            return False
        body = body[1:]
    if not body or body.count(".") > 1:
        return False
    whole, separator, fractional = body.partition(".")
    if not _is_uint_text(whole):
        return False
    return not separator or _is_ascii_digits(fractional)


def _reference_period_parts(value: Any) -> tuple[int, int] | None:
    if (
        not isinstance(value, str)
        or len(value) != 7
        or value[4] != "-"
        or not _is_ascii_digits(value[:4])
        or not _is_ascii_digits(value[5:])
    ):
        return None
    month = int(value[5:])
    if not 1 <= month <= 12:
        return None
    return int(value[:4]), month


def _is_utc_timestamp(value: Any) -> bool:
    if (
        not isinstance(value, str)
        or len(value) != 20
        or value[4] != "-"
        or value[7] != "-"
        or value[10] != "T"
        or value[13] != ":"
        or value[16] != ":"
        or value[19] != "Z"
        or not _is_ascii_digits(
            value[0:4]
            + value[5:7]
            + value[8:10]
            + value[11:13]
            + value[14:16]
            + value[17:19]
        )
    ):
        return False
    try:
        datetime(
            int(value[0:4]),
            int(value[5:7]),
            int(value[8:10]),
            int(value[11:13]),
            int(value[14:16]),
            int(value[17:19]),
        )
    except ValueError:
        return False
    return True


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


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hard_false_gates() -> dict[str, bool]:
    return {name: False for name in HARD_FALSE_GATES}


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
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_json_keys,
            parse_constant=_reject_nonfinite_json_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ProfileError(location + " is not strict UTF-8 JSON") from error
    if not isinstance(value, dict):
        fail(location + " must contain one JSON object")
    return value


def _canonical_semantic_hash(document: Mapping[str, Any]) -> str:
    copy = json.loads(canonical_json_bytes(document).decode("utf-8"))
    artifact = copy.get("artifact")
    if not isinstance(artifact, dict):
        fail("profile artifact block is missing")
    if set(artifact).isdisjoint({"content_sha256"}):
        fail("profile semantic hash field is missing")
    del artifact["content_sha256"]
    return sha256_bytes(canonical_json_bytes(copy))


def _read_pinned_regular_file(path: Path, location: str) -> bytes:
    if not isinstance(path, Path) or not path.is_absolute():
        fail(location + " path must be absolute")
    supplied = Path(os.fspath(path))
    absolute = Path(os.path.abspath(os.fspath(path)))
    if supplied != absolute:
        fail(location + " path must use canonical absolute spelling")
    try:
        resolved = absolute.resolve(strict=True)
    except OSError as error:
        raise ProfileError(location + " path cannot be resolved") from error
    if resolved != absolute:
        fail(location + " path contains a symbolic-link or alias component")
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(absolute, flags)
    except OSError as error:
        raise ProfileError(location + " could not be opened safely") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            fail(location + " must be a single-link regular file")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_RAW_BYTES:
                fail(location + " exceeds the raw-byte bound")
            chunks.append(chunk)
        path_state = os.stat(absolute, follow_symlinks=False)
        after = os.fstat(descriptor)
        stable_fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns")
        if (
            not stat.S_ISREG(path_state.st_mode)
            or path_state.st_nlink != 1
            or any(
                getattr(before, field) != getattr(path_state, field)
                for field in stable_fields
            )
            or any(
                getattr(before, field) != getattr(after, field)
                for field in stable_fields
            )
        ):
            fail(location + " changed during its pinned read")
        data = b"".join(chunks)
        if len(data) != before.st_size:
            fail(location + " size changed during its pinned read")
        return data
    finally:
        os.close(descriptor)


def _load_profile_and_contract() -> tuple[dict[str, Any], dict[str, Any]]:
    profile_bytes = _read_pinned_regular_file(PROFILE_PATH, "profile")
    if sha256_bytes(profile_bytes) != EXPECTED_PROFILE_PHYSICAL_SHA256:
        fail("profile physical SHA-256 drifted")
    profile = parse_json_bytes(profile_bytes, "profile")
    if profile.get("artifact", {}).get("schema_version") != PROFILE_SCHEMA_VERSION:
        fail("profile schema version drifted")
    expected_semantic = profile.get("artifact", {}).get("content_sha256")
    if (
        not _is_sha256_text(expected_semantic)
        or _canonical_semantic_hash(profile) != expected_semantic
    ):
        fail("profile semantic SHA-256 is invalid")
    contract_bytes = _read_pinned_regular_file(CONTRACT_PATH, "contract")
    if sha256_bytes(contract_bytes) != EXPECTED_CONTRACT_PHYSICAL_SHA256:
        fail("prospective-v2 contract physical SHA-256 drifted")
    try:
        contract = tomllib.loads(contract_bytes.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        raise ProfileError("prospective-v2 contract is not strict TOML") from error
    _validate_profile(profile, contract)
    return profile, contract


def load_profile() -> dict[str, Any]:
    """Return a detached copy after mandatory profile and contract checks."""

    profile, _ = _load_profile_and_contract()
    return parse_json_bytes(canonical_json_bytes(profile), "detached profile")


def _required_text(record: Mapping[str, Any], key: str, location: str) -> str:
    value = record.get(key)
    if not isinstance(value, str) or not value:
        fail(location + "." + key + " must be nonempty text")
    return value


def _required_exact_int(record: Mapping[str, Any], key: str, location: str) -> int:
    value = record.get(key)
    if type(value) is not int or value < 0:
        fail(location + "." + key + " must be an exact nonnegative integer")
    return value


def _validate_profile(profile: Mapping[str, Any], contract: Mapping[str, Any]) -> None:
    if set(profile) != {
        "artifact",
        "boundary",
        "gates",
        "ooxml_policy",
        "profiles",
        "structures",
    }:
        fail("profile top-level keys drifted")
    artifact = profile["artifact"]
    if not isinstance(artifact, dict) or set(artifact) != {
        "schema_version",
        "status",
        "role",
        "canonicalization",
        "content_sha256",
        "prospective_contract_sha256",
    }:
        fail("profile artifact block drifted")
    if (
        artifact["status"] != STATUS
        or artifact["role"] != ROLE
        or artifact["canonicalization"] != CANONICALIZATION
        or artifact["prospective_contract_sha256"]
        != EXPECTED_CONTRACT_PHYSICAL_SHA256
    ):
        fail("profile artifact ceiling or source pin drifted")
    boundary = profile["boundary"]
    if not isinstance(boundary, dict):
        fail("profile boundary block is malformed")
    required_false = (
        "current_bodies_claimed_as_future_compatible",
        "current_bodies_claimed_as_origin_evidence",
        "provider_origin_authenticated",
        "future_capture_completed",
        "future_parser_qualified",
        "self_accepted",
    )
    if any(boundary.get(key) is not False for key in required_false):
        fail("profile evidence boundary rose above its ceiling")
    if boundary.get("current_observation_date") != "2026-08-08":
        fail("profile observation date drifted")
    gates = profile["gates"]
    if not isinstance(gates, dict) or gates != hard_false_gates():
        fail("profile gates are not the exact hard-false gate set")
    policy = profile["ooxml_policy"]
    if not isinstance(policy, dict) or any(
        policy.get(key) is not True
        for key in (
            "case_unique_members_required",
            "bom_free_utf8_xml_required",
            "crc_required",
            "relationships_required",
            "content_types_required",
            "xml_preflight_by_resolved_content_type",
            "relationship_part_content_types_exact",
            "relationship_target_content_types_exact",
            "external_relationships_forbidden",
            "dtd_entity_processing_instructions_forbidden",
            "formulas_forbidden",
            "error_cells_forbidden",
            "source_verification_always_on",
            "single_link_absolute_paths_required",
        )
    ):
        fail("profile OOXML policy drifted")
    records = profile["profiles"]
    if not isinstance(records, list) or len(records) != 5:
        fail("profile must contain exactly five prospective records")
    contract_requirements = {
        item.get("requirement_id"): item
        for item in contract.get("requirements", [])
        if isinstance(item, dict)
    }
    contract_events = {
        item.get("event_id"): item
        for item in contract.get("fixed_events", [])
        if isinstance(item, dict)
    }
    for index, (profile_id, record) in enumerate(
        zip(EXPECTED_PROFILE_IDS, records), start=1
    ):
        location = "profile record " + str(index)
        if not isinstance(record, dict):
            fail(location + " is malformed")
        expected = EXPECTED_BINDINGS[profile_id]
        for key in (
            "profile_id",
            "requirement_id",
            "event_id",
            "reference_period",
            "scheduled_timestamp_utc",
            "capture_deadline_utc",
            "source_url",
            "selector",
            "parser_kind",
        ):
            expected_value = profile_id if key == "profile_id" else expected[key]
            if record.get(key) != expected_value:
                fail(location + "." + key + " drifted")
        if record.get("planned_capture_status") != "PLANNED_NOT_CAPTURED":
            fail(location + " falsely claims a completed planned capture")
        observed = record.get("observed_current")
        if not isinstance(observed, dict):
            fail(location + " lacks observed-current diagnostics")
        if observed.get("claim") != "PRESENT_DAY_SCHEMA_OBSERVATION_ONLY":
            fail(location + " observed-current claim drifted")
        if not _is_sha256_text(_required_text(observed, "raw_sha256", location)):
            fail(location + " observed raw hash is malformed")
        _required_exact_int(observed, "raw_byte_count", location)
        requirement = contract_requirements.get(expected["requirement_id"])
        event = contract_events.get(expected["event_id"])
        if not isinstance(requirement, dict) or not isinstance(event, dict):
            fail(location + " is absent from the frozen contract")
        contract_profiles = requirement.get("artifact_profiles")
        if (
            not isinstance(contract_profiles, dict)
            or contract_profiles.get(profile_id) != expected["selector"]
        ):
            fail(location + " selector differs from the frozen contract")
        if (
            event.get("source_id") != requirement.get("source_id")
            or event.get("reference_period") != expected["reference_period"]
            or event.get("scheduled_timestamp_utc")
            != expected["scheduled_timestamp_utc"]
            or event.get("capture_deadline_utc")
            != expected["capture_deadline_utc"]
            or expected["requirement_id"] not in event.get("requirement_ids", [])
        ):
            fail(location + " event binding differs from the frozen contract")
    structures = profile["structures"]
    if not isinstance(structures, dict) or set(structures) != {
        "m3_full_table6",
        "m3_advance_total",
        "mrts",
        "mwts_adjusted",
        "mwts_not_adjusted",
    }:
        fail("profile structure topology drifted")


def excel_column_number(letters: str) -> int:
    result = 0
    for character in letters:
        result = result * 26 + ord(character) - ord("A") + 1
    return result


def excel_column_letters(number: int) -> str:
    if type(number) is not int or number < 1:
        fail("Excel column number must be a positive integer")
    result = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        result = chr(ord("A") + remainder) + result
    return result


def split_cell_reference(reference: str) -> tuple[int, int]:
    if not isinstance(reference, str) or not reference:
        fail("malformed worksheet cell reference: " + repr(reference))
    split = 0
    while split < len(reference) and "A" <= reference[split] <= "Z":
        split += 1
    letters = reference[:split]
    row_text = reference[split:]
    if not letters or not _is_positive_int_text(row_text):
        fail("malformed worksheet cell reference: " + repr(reference))
    return excel_column_number(letters), int(row_text)


def _xml_root(
    data: bytes,
    location: str,
    expected_tag: str | None = None,
) -> ET.Element:
    byte_order_marks = (
        b"\xef\xbb\xbf",
        b"\xff\xfe",
        b"\xfe\xff",
        b"\x00\x00\xfe\xff",
        b"\xff\xfe\x00\x00",
    )
    if data.startswith(byte_order_marks):
        fail(location + " must be BOM-free UTF-8 XML")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ProfileError(location + " must be strict UTF-8 XML") from error
    if any(
        ord(character) < 32 and character not in "\t\n\r"
        for character in text
    ):
        fail(location + " contains a forbidden XML control character")
    remainder = text
    if text.startswith("<?xml"):
        if len(text) == 5 or text[5] not in " \t\r\n":
            fail(location + " contains a forbidden processing instruction")
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
    return root


def _safe_zip_payloads(
    raw_bytes: bytes,
) -> tuple[dict[str, bytes], str, int]:
    if not raw_bytes.startswith(b"PK\x03\x04"):
        fail("workbook does not begin with an OOXML ZIP signature")
    try:
        archive = zipfile.ZipFile(io.BytesIO(raw_bytes), "r")
    except (zipfile.BadZipFile, OSError) as error:
        raise ProfileError("workbook is not a readable ZIP archive") from error
    with archive:
        infos = archive.infolist()
        if not 1 <= len(infos) <= MAX_ZIP_MEMBERS:
            fail("ZIP member count is outside the closed bound")
        names = [info.filename for info in infos]
        if len(names) != len(set(names)):
            fail("ZIP member names are not unique")
        if len(names) != len({name.casefold() for name in names}):
            fail("ZIP member names are not case-unique")
        total_uncompressed = 0
        for info in infos:
            name = info.filename
            pure = PurePosixPath(name)
            lowered = name.casefold()
            if (
                not name
                or name.endswith("/")
                or name.startswith("/")
                or "\\" in name
                or "\x00" in name
                or pure.is_absolute()
                or any(part in ("", ".", "..") for part in pure.parts)
                or posixpath.normpath(name) != name
                or any(token in lowered for token in FORBIDDEN_MEMBER_TOKENS)
            ):
                fail("ZIP contains an unsafe or forbidden member: " + repr(name))
            if info.flag_bits & 0x1:
                fail("ZIP contains an encrypted member")
            if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                fail("ZIP contains an unsupported compression method")
            unix_mode = (info.external_attr >> 16) & 0xFFFF
            if (
                info.create_system == 3
                and unix_mode
                and not stat.S_ISREG(unix_mode)
            ):
                fail("ZIP contains a non-regular Unix member")
            if info.file_size > MAX_MEMBER_BYTES:
                fail("ZIP member exceeds its uncompressed size bound")
            total_uncompressed += info.file_size
            if total_uncompressed > MAX_TOTAL_UNCOMPRESSED_BYTES:
                fail("ZIP exceeds its total uncompressed size bound")
            if info.compress_size == 0:
                if info.file_size != 0:
                    fail("ZIP member has an invalid compression ratio")
            elif info.file_size / info.compress_size > MAX_COMPRESSION_RATIO:
                fail("ZIP member exceeds its compression-ratio bound")
        bad_member = archive.testzip()
        if bad_member is not None:
            fail("ZIP CRC validation failed for " + bad_member)
        payloads: dict[str, bytes] = {}
        manifest: list[dict[str, Any]] = []
        for info in infos:
            try:
                payload = archive.read(info)
            except (zipfile.BadZipFile, RuntimeError, EOFError) as error:
                raise ProfileError("ZIP member could not be read safely") from error
            if len(payload) != info.file_size:
                fail("ZIP member size differs from its directory record")
            payloads[info.filename] = payload
            manifest.append(
                {
                    "name": info.filename,
                    "compressed_bytes": info.compress_size,
                    "uncompressed_bytes": info.file_size,
                    "crc32": f"{info.CRC:08x}",
                    "sha256": sha256_bytes(payload),
                }
            )
        return (
            payloads,
            sha256_bytes(canonical_json_bytes(manifest)),
            len(infos),
        )


def _content_types(
    payloads: Mapping[str, bytes],
) -> tuple[dict[str, str], str]:
    data = payloads.get("[Content_Types].xml")
    if data is None:
        fail("OOXML package lacks [Content_Types].xml")
    root = _xml_root(
        data,
        "[Content_Types].xml",
        CONTENT_TYPES + "Types",
    )
    defaults: dict[str, str] = {}
    overrides: dict[str, str] = {}
    manifest: list[dict[str, str]] = []
    for child in root:
        if child.tag == CONTENT_TYPES + "Default":
            extension = child.get("Extension")
            content_type = child.get("ContentType")
            if not extension or not content_type:
                fail("content-type default is incomplete")
            key = extension.casefold()
            if key in defaults:
                fail("content-type default extension is duplicated")
            defaults[key] = content_type
            manifest.append(
                {
                    "kind": "default",
                    "name": extension,
                    "content_type": content_type,
                }
            )
        elif child.tag == CONTENT_TYPES + "Override":
            part_name = child.get("PartName")
            content_type = child.get("ContentType")
            if not part_name or not content_type or not part_name.startswith("/"):
                fail("content-type override is incomplete")
            name = part_name[1:]
            if (
                not name
                or "\\" in name
                or ".." in PurePosixPath(name).parts
                or posixpath.normpath(name) != name
            ):
                fail("content-type override has an unsafe part name")
            if name in overrides or name.casefold() in {
                existing.casefold() for existing in overrides
            }:
                fail("content-type override part is not case-unique")
            overrides[name] = content_type
            manifest.append(
                {
                    "kind": "override",
                    "name": part_name,
                    "content_type": content_type,
                }
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
        suffix = "rels" if name.endswith(".rels") else PurePosixPath(name).suffix[1:]
        if not suffix or suffix.casefold() not in defaults:
            fail("ZIP member lacks a resolvable content type: " + name)
        resolved[name] = defaults[suffix.casefold()]
    for name in overrides:
        if name not in payloads:
            fail("content-type override targets an absent part")
    required = {
        "xl/workbook.xml": WORKBOOK_CONTENT_TYPE,
        "xl/styles.xml": STYLES_CONTENT_TYPE,
        "xl/sharedStrings.xml": SHARED_STRINGS_CONTENT_TYPE,
    }
    for name, content_type in required.items():
        if resolved.get(name) != content_type:
            fail(name + " has the wrong OOXML content type")
    if any(
        content_type != RELATIONSHIPS_CONTENT_TYPE
        for name, content_type in resolved.items()
        if name.casefold().endswith(".rels")
    ):
        fail("OOXML relationship part content type is not exact")
    if any("macroenabled" in value.casefold() for value in resolved.values()):
        fail("macro-enabled OOXML content is forbidden")
    return resolved, sha256_bytes(canonical_json_bytes(manifest))


def _is_xml_content_type(content_type: str) -> bool:
    mime = content_type.partition(";")[0].strip().casefold()
    return mime in ("application/xml", "text/xml") or mime.endswith("+xml")


def _preflight_xml_typed_parts(
    payloads: Mapping[str, bytes],
    content_types: Mapping[str, str],
) -> None:
    for name, content_type in content_types.items():
        if _is_xml_content_type(content_type):
            _xml_root(payloads[name], name)


def _validate_relationship_content_types(
    relationships: Mapping[str, Mapping[str, tuple[str, str]]],
    content_types: Mapping[str, str],
) -> None:
    for records in relationships.values():
        for target, relation_type in records.values():
            expected = next(
                (
                    content_type
                    for candidate_type, content_type in RELATION_CONTENT_TYPE_RULES
                    if candidate_type == relation_type
                ),
                None,
            )
            if expected is None or content_types.get(target) != expected:
                fail("OOXML relationship target content type is not exact")


def _relationship_source_part(relationship_part: str) -> str:
    if relationship_part == "_rels/.rels":
        return ""
    path = PurePosixPath(relationship_part)
    if len(path.parts) < 3 or path.parts[-2] != "_rels":
        fail("relationship part has an invalid location")
    filename = path.name
    if not filename.endswith(".rels"):
        fail("relationship part has an invalid suffix")
    return str(path.parent.parent / filename[: -len(".rels")])


def _resolve_relationship_target(source_part: str, target: str) -> str:
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
        fail("OOXML relationship target is unsafe")
    base = posixpath.dirname(source_part)
    resolved = posixpath.normpath(posixpath.join(base, parsed.path))
    if resolved.startswith("../") or resolved in ("", ".", ".."):
        fail("OOXML relationship escapes the package")
    return resolved


def _relationships(
    payloads: Mapping[str, bytes],
) -> tuple[dict[str, dict[str, tuple[str, str]]], str]:
    relationship_parts = sorted(
        name for name in payloads if name.endswith(".rels")
    )
    if "_rels/.rels" not in relationship_parts:
        fail("OOXML package lacks the root relationship part")
    by_source: dict[str, dict[str, tuple[str, str]]] = {}
    manifest: list[dict[str, str]] = []
    for part_name in relationship_parts:
        source = _relationship_source_part(part_name)
        if source in by_source:
            fail("OOXML source has duplicate relationship parts")
        if source and source not in payloads:
            fail("OOXML relationship part belongs to an absent source")
        root = _xml_root(
            payloads[part_name], part_name, PKG_REL + "Relationships"
        )
        records: dict[str, tuple[str, str]] = {}
        for relation in root:
            if relation.tag != PKG_REL + "Relationship":
                fail("relationship XML contains an unsupported child")
            relation_id = relation.get("Id")
            target = relation.get("Target")
            relation_type = relation.get("Type")
            target_mode = relation.get("TargetMode", "Internal")
            if not relation_id or not target or not relation_type:
                fail("OOXML relationship is incomplete")
            if relation_id in records:
                fail("OOXML relationship Id is duplicated")
            if target_mode != "Internal":
                fail("external OOXML relationship is forbidden")
            if any(
                token in relation_type.casefold()
                for token in FORBIDDEN_RELATION_TOKENS
            ):
                fail("forbidden OOXML relationship type")
            if relation_type not in ALLOWED_RELATION_TYPES:
                fail("unsupported OOXML relationship type")
            resolved = _resolve_relationship_target(source, target)
            if resolved not in payloads:
                fail("OOXML relationship targets an absent part")
            records[relation_id] = (resolved, relation_type)
            manifest.append(
                {
                    "source": source,
                    "id": relation_id,
                    "target": resolved,
                    "type": relation_type,
                    "target_mode": target_mode,
                }
            )
        by_source[source] = records
    root_office = [
        target
        for target, relation_type in by_source.get("", {}).values()
        if relation_type == DOC_REL_NS + "/officeDocument"
    ]
    if root_office != ["xl/workbook.xml"]:
        fail("root office-document relationship is not exact")
    reachable: set[str] = set()
    pending = [target for target, _ in by_source.get("", {}).values()]
    while pending:
        target = pending.pop()
        if target in reachable:
            continue
        reachable.add(target)
        pending.extend(
            child_target for child_target, _ in by_source.get(target, {}).values()
        )
    relationship_set = set(relationship_parts)
    substantive_parts = (
        set(payloads) - relationship_set - {"[Content_Types].xml"}
    )
    if reachable != substantive_parts:
        fail("OOXML package contains an unreachable or unbound substantive part")
    return by_source, sha256_bytes(canonical_json_bytes(manifest))


def _shared_strings(data: bytes) -> tuple[list[str], str, int]:
    root = _xml_root(data, "xl/sharedStrings.xml", MAIN + "sst")
    values: list[str] = []
    for child in root:
        if child.tag == MAIN + "extLst":
            continue
        if child.tag != MAIN + "si":
            fail("shared-strings XML contains an unsupported child")
        text_nodes = list(child.iter(MAIN + "t"))
        if not text_nodes:
            fail("shared-string item contains no text node")
        values.append("".join(node.text or "" for node in text_nodes))
    unique_count = root.get("uniqueCount")
    count = root.get("count")
    if unique_count is None or (
        not _is_uint_text(unique_count)
        or int(unique_count) != len(values)
    ):
        fail("shared-strings uniqueCount is inconsistent")
    if count is None or (
        not _is_uint_text(count) or int(count) < len(values)
    ):
        fail("shared-strings count is inconsistent")
    return values, sha256_bytes(canonical_json_bytes(values)), int(count)


def _styles(data: bytes) -> tuple[int, str]:
    root = _xml_root(data, "xl/styles.xml", MAIN + "styleSheet")
    cell_formats = root.find(MAIN + "cellXfs")
    if cell_formats is None:
        fail("styles XML lacks cellXfs")
    formats = cell_formats.findall(MAIN + "xf")
    if not formats:
        fail("styles XML contains no cell formats")
    count = cell_formats.get("count")
    if count is not None and (
        not _is_uint_text(count) or int(count) != len(formats)
    ):
        fail("styles cellXfs count is inconsistent")
    semantic = [dict(sorted(item.attrib.items())) for item in formats]
    return len(formats), sha256_bytes(canonical_json_bytes(semantic))


def _parse_sheet(
    name: str,
    part_name: str,
    data: bytes,
    shared_strings: Sequence[str],
    style_count: int,
) -> Sheet:
    root = _xml_root(data, part_name, MAIN + "worksheet")
    dimension_nodes = root.findall(MAIN + "dimension")
    if len(dimension_nodes) != 1:
        fail(name + " must contain exactly one worksheet dimension")
    dimension = dimension_nodes[0].get("ref")
    if not dimension:
        fail(name + " worksheet dimension is missing its reference")
    if dimension.count(":") == 1:
        start, end = dimension.split(":", 1)
    elif ":" not in dimension:
        start = end = dimension
    else:
        fail(name + " worksheet dimension is malformed")
    start_column, start_row = split_cell_reference(start)
    end_column, end_row = split_cell_reference(end)
    if start_column > end_column or start_row > end_row:
        fail(name + " worksheet dimension is reversed")
    sheet_data_nodes = root.findall(MAIN + "sheetData")
    if len(sheet_data_nodes) != 1:
        fail(name + " must contain exactly one sheetData element")
    cells: dict[tuple[int, int], Cell] = {}
    previous_row = 0
    for row_element in sheet_data_nodes[0]:
        if row_element.tag != MAIN + "row":
            fail(name + " sheetData contains an unsupported child")
        row_text = row_element.get("r")
        if not _is_positive_int_text(row_text):
            fail(name + " row has a malformed index")
        row_number = int(row_text)
        if row_number <= previous_row:
            fail(name + " row order is not strictly increasing")
        previous_row = row_number
        previous_column = 0
        for cell_element in row_element:
            if cell_element.tag != MAIN + "c":
                fail(name + " row contains an unsupported child")
            reference = cell_element.get("r")
            if reference is None:
                fail(name + " cell lacks a reference")
            column, referenced_row = split_cell_reference(reference)
            if referenced_row != row_number or column <= previous_column:
                fail(name + " cell axis is duplicated or out of order")
            previous_column = column
            key = (row_number, column)
            if key in cells:
                fail(name + " contains a duplicate cell")
            if cell_element.find(MAIN + "f") is not None:
                fail(name + " contains a forbidden formula")
            if cell_element.find(MAIN + "is") is not None:
                fail(name + " contains a forbidden inline string")
            if any(child.tag != MAIN + "v" for child in cell_element):
                fail(name + " cell contains an unsupported child")
            cell_type = cell_element.get("t", "n")
            if cell_type == "e":
                fail(name + " contains a forbidden error cell")
            if cell_type not in ("n", "s"):
                fail(name + " contains an unsupported cell type: " + cell_type)
            style_text = cell_element.get("s", "0")
            if not _is_uint_text(style_text):
                fail(name + " contains a malformed style index")
            style_index = int(style_text)
            if style_index >= style_count:
                fail(name + " cell refers to an absent style")
            value_nodes = cell_element.findall(MAIN + "v")
            if len(value_nodes) > 1:
                fail(name + " cell contains duplicate values")
            raw_value = None
            value = None
            if value_nodes:
                raw_value = value_nodes[0].text
                if raw_value is None:
                    fail(name + " cell contains an empty value element")
                if cell_type == "s":
                    if not _is_uint_text(raw_value):
                        fail(name + " shared-string index is malformed")
                    index = int(raw_value)
                    if index >= len(shared_strings):
                        fail(name + " shared-string index is out of range")
                    value = shared_strings[index]
                else:
                    if not _is_decimal_text(raw_value):
                        fail(name + " numeric XML lexeme is not exact decimal text")
                    value = raw_value
            cells[key] = Cell(
                reference=reference,
                row=row_number,
                column=column,
                cell_type=cell_type,
                style_index=style_index,
                value=value,
                raw_value=raw_value,
            )
    if any(
        not (
            start_row <= row <= end_row
            and start_column <= column <= end_column
        )
        for row, column in cells
    ):
        fail(name + " contains a cell outside its declared dimension")
    return Sheet(
        name=name,
        part_name=part_name,
        dimension=dimension,
        cells=cells,
        xml_sha256=sha256_bytes(data),
    )


def parse_workbook(path: Path) -> Workbook:
    """Parse one absolute external XLSX after mandatory source-file checks."""

    raw_bytes = _read_pinned_regular_file(path, "external workbook")
    payloads, member_hash, member_count = _safe_zip_payloads(raw_bytes)
    required_parts = {
        "[Content_Types].xml",
        "_rels/.rels",
        "xl/workbook.xml",
        "xl/_rels/workbook.xml.rels",
        "xl/sharedStrings.xml",
        "xl/styles.xml",
    }
    if not required_parts.issubset(payloads):
        fail("OOXML workbook lacks required package parts")
    content_types, content_types_hash = _content_types(payloads)
    _preflight_xml_typed_parts(payloads, content_types)
    relationships, relationship_hash = _relationships(payloads)
    _validate_relationship_content_types(relationships, content_types)
    shared, shared_hash, shared_reference_count = _shared_strings(
        payloads["xl/sharedStrings.xml"]
    )
    style_count, styles_hash = _styles(payloads["xl/styles.xml"])
    workbook_root = _xml_root(
        payloads["xl/workbook.xml"], "xl/workbook.xml", MAIN + "workbook"
    )
    sheets_nodes = workbook_root.findall(MAIN + "sheets")
    if len(sheets_nodes) != 1:
        fail("workbook must contain exactly one sheets element")
    records = sheets_nodes[0].findall(MAIN + "sheet")
    if not records:
        fail("workbook contains no sheets")
    workbook_rels = relationships.get("xl/workbook.xml", {})
    sheet_names: list[str] = []
    relation_ids: set[str] = set()
    sheet_ids: set[int] = set()
    sheets: dict[str, Sheet] = {}
    sheet_targets: set[str] = set()
    for record in records:
        name = record.get("name")
        relation_id = record.get(DOC_REL + "id")
        sheet_id_text = record.get("sheetId")
        if (
            set(record.attrib) != {"name", "sheetId", DOC_REL + "id"}
            or not name
            or not relation_id
            or sheet_id_text is None
            or not _is_positive_int_text(sheet_id_text)
        ):
            fail("workbook sheet record is incomplete")
        if name in sheets or name.casefold() in {
            existing.casefold() for existing in sheets
        }:
            fail("workbook sheet names are not case-unique")
        sheet_id = int(sheet_id_text)
        if relation_id in relation_ids or sheet_id in sheet_ids:
            fail("workbook sheet identity is duplicated")
        relation_ids.add(relation_id)
        sheet_ids.add(sheet_id)
        relation = workbook_rels.get(relation_id)
        if relation is None or relation[1] != DOC_REL_NS + "/worksheet":
            fail("workbook sheet relationship is unresolved")
        target = relation[0]
        if (
            not target.startswith("xl/worksheets/")
            or content_types.get(target) != WORKSHEET_CONTENT_TYPE
        ):
            fail("workbook sheet target is not an OOXML worksheet")
        if target in sheet_targets:
            fail("workbook sheet target is duplicated")
        sheet_targets.add(target)
        sheet_names.append(name)
        sheets[name] = _parse_sheet(
            name,
            target,
            payloads[target],
            shared,
            style_count,
        )
    worksheet_relation_ids = {
        relation_id
        for relation_id, (_, relation_type) in workbook_rels.items()
        if relation_type == DOC_REL_NS + "/worksheet"
    }
    if worksheet_relation_ids != relation_ids:
        fail("workbook contains an unbound or missing worksheet relationship")
    worksheet_parts = {
        name
        for name, content_type in content_types.items()
        if content_type == WORKSHEET_CONTENT_TYPE
    }
    if worksheet_parts != sheet_targets:
        fail("OOXML package worksheet parts differ from the workbook topology")
    for relation_type, expected_target in (
        (DOC_REL_NS + "/sharedStrings", "xl/sharedStrings.xml"),
        (DOC_REL_NS + "/styles", "xl/styles.xml"),
    ):
        targets = [
            target
            for target, candidate_type in workbook_rels.values()
            if candidate_type == relation_type
        ]
        if targets != [expected_target]:
            fail("workbook support-part relationship is not exact")
    shared_indexes = [
        int(cell.raw_value)
        for sheet in sheets.values()
        for cell in sheet.cells.values()
        if cell.cell_type == "s" and cell.raw_value is not None
    ]
    if len(shared_indexes) != shared_reference_count:
        fail("shared-strings count differs from worksheet references")
    if set(shared_indexes) != set(range(len(shared))):
        fail("shared-strings table contains an unreferenced item")
    return Workbook(
        raw_sha256=sha256_bytes(raw_bytes),
        raw_byte_count=len(raw_bytes),
        zip_member_count=member_count,
        zip_member_manifest_sha256=member_hash,
        content_types_manifest_sha256=content_types_hash,
        relationship_manifest_sha256=relationship_hash,
        shared_strings_semantic_sha256=shared_hash,
        styles_semantic_sha256=styles_hash,
        sheet_names=tuple(sheet_names),
        sheets=sheets,
    )


def _cell(sheet: Sheet, reference: str) -> Cell | None:
    column, row = split_cell_reference(reference)
    return sheet.cells.get((row, column))


def _required_cell(sheet: Sheet, reference: str) -> Cell:
    cell = _cell(sheet, reference)
    if cell is None or cell.value is None:
        fail(sheet.name + "!" + reference + " is required")
    return cell


def _required_display(sheet: Sheet, reference: str) -> str:
    return _required_cell(sheet, reference).value or ""


def _expect_text(sheet: Sheet, reference: str, expected: str) -> None:
    cell = _required_cell(sheet, reference)
    if cell.cell_type != "s" or cell.value != expected:
        fail(sheet.name + "!" + reference + " text drifted")


def _expect_numeric_text(sheet: Sheet, reference: str, expected: str) -> None:
    cell = _required_cell(sheet, reference)
    if cell.cell_type != "n" or cell.raw_value != expected:
        fail(sheet.name + "!" + reference + " numeric text drifted")


def _expect_absent_value(sheet: Sheet, reference: str) -> None:
    cell = _cell(sheet, reference)
    if cell is not None and cell.value is not None:
        fail(sheet.name + "!" + reference + " must not contain a value")


def _exact_nonnegative_integer(sheet: Sheet, reference: str) -> int:
    cell = _required_cell(sheet, reference)
    if (
        cell.cell_type != "n"
        or cell.raw_value is None
        or not _is_uint_text(cell.raw_value)
    ):
        fail(sheet.name + "!" + reference + " must be an exact integer cell")
    return int(cell.raw_value)


def _exact_ratio(sheet: Sheet, reference: str) -> str:
    cell = _required_cell(sheet, reference)
    if (
        cell.cell_type != "n"
        or cell.raw_value is None
        or not _is_decimal_text(cell.raw_value, nonnegative=True)
    ):
        fail(sheet.name + "!" + reference + " must be an exact ratio cell")
    return _canonical_decimal_text(cell.raw_value)


def _canonical_decimal_text(value: str) -> str:
    if not _is_decimal_text(value):
        fail("decimal text is malformed")
    negative = value.startswith("-")
    body = value[1:] if negative else value
    if "." in body:
        whole, fractional = body.split(".", 1)
        fractional = fractional.rstrip("0")
        body = whole if not fractional else whole + "." + fractional
    if body == "0":
        negative = False
    return ("-" if negative else "") + body


def _profile_vector_hash(values: Sequence[Any]) -> str:
    return sha256_bytes(canonical_json_bytes(list(values)))


def _reference_parts(reference_period: str) -> tuple[int, int]:
    parts = _reference_period_parts(reference_period)
    if parts is None:
        fail("reference period is malformed")
    return parts


def _previous_month(year: int, month: int, count: int = 1) -> tuple[int, int]:
    index = year * 12 + month - 1 - count
    return index // 12, index % 12 + 1


def _month_axis(start: str, end: str) -> list[tuple[int, int]]:
    start_year, start_month = _reference_parts(start)
    end_year, end_month = _reference_parts(end)
    start_index = start_year * 12 + start_month - 1
    end_index = end_year * 12 + end_month - 1
    if end_index < start_index:
        fail("month axis ends before it starts")
    return [
        (index // 12, index % 12 + 1)
        for index in range(start_index, end_index + 1)
    ]


def _workbook_record(
    workbook: Workbook,
    selected_sheets: Sequence[str],
) -> dict[str, Any]:
    return {
        "raw_sha256": workbook.raw_sha256,
        "raw_byte_count": workbook.raw_byte_count,
        "zip_member_count": workbook.zip_member_count,
        "zip_member_manifest_sha256": workbook.zip_member_manifest_sha256,
        "content_types_manifest_sha256": (
            workbook.content_types_manifest_sha256
        ),
        "relationship_manifest_sha256": (
            workbook.relationship_manifest_sha256
        ),
        "shared_strings_semantic_sha256": (
            workbook.shared_strings_semantic_sha256
        ),
        "styles_semantic_sha256": workbook.styles_semantic_sha256,
        "sheet_names": list(workbook.sheet_names),
        "selected_sheets": [
            {
                "name": name,
                "part_name": workbook.sheets[name].part_name,
                "dimension": workbook.sheets[name].dimension,
                "worksheet_xml_sha256": workbook.sheets[name].xml_sha256,
            }
            for name in selected_sheets
        ],
    }


def _assert_sheet_topology(
    workbook: Workbook,
    structure: Mapping[str, Any],
) -> None:
    names = structure.get("sheet_names")
    if not isinstance(names, list) or any(not isinstance(name, str) for name in names):
        fail("profile sheet topology is malformed")
    if workbook.sheet_names != tuple(names):
        fail("workbook sheet topology drifted")


def _m3_full_header(sheet: Sheet, reference_period: str) -> None:
    year, month = _reference_parts(reference_period)
    previous_year, previous_month = _previous_month(year, month)
    older_year, older_month = _previous_month(year, month, 2)
    expected = {
        "C6": "Seasonally Adjusted",
        "I6": "Not Seasonally Adjusted",
        "C7": "Monthly",
        "F7": "Percent Change",
        "I7": "Monthly",
        "M7": "% Change",
        "A8": "Industry",
        "C9": M3_MONTHS_FULL[month - 1],
        "D9": M3_MONTHS_FULL[previous_month - 1],
        "E9": M3_MONTHS_FULL[older_month - 1],
        "C10": str(year) + "p",
        "D10": str(previous_year) + "r",
        "I9": M3_MONTHS_FULL[month - 1],
        "J9": M3_MONTHS_FULL[previous_month - 1],
        "K9": M3_MONTHS_FULL[older_month - 1],
        "I10": str(year) + "p",
        "J10": str(previous_year) + "r",
        "L9": M3_MONTHS_FULL[month - 1],
        "M8": M3_MONTHS_FULL[month - 1],
        "M9": str(year) + "/",
    }
    for reference, text in expected.items():
        _expect_text(sheet, reference, text)
    for reference, text in {
        "E10": str(older_year),
        "K10": str(older_year),
        "L10": str(year - 1),
        "M10": str(year - 1),
    }.items():
        _expect_numeric_text(sheet, reference, text)


def _parse_m3_full(
    workbook: Workbook,
    structure: Mapping[str, Any],
    reference_period: str,
) -> dict[str, Any]:
    _assert_sheet_topology(workbook, structure)
    sheet = workbook.sheets.get("Table 6")
    if sheet is None:
        fail("M3 full workbook lacks the exact Table 6 sheet")
    _expect_text(
        sheet,
        "A2",
        "Table 6.  Value of Manufacturers' Inventories, by Stage of "
        "Fabrication, by Industry Group1  ",
    )
    _expect_text(
        sheet,
        "A5",
        "[Estimates are shown in millions of dollars and are based on data "
        "from the Manufacturers' Shipments, Inventories, and Orders Survey.]  ",
    )
    _m3_full_header(sheet, reference_period)
    footnote = _required_display(sheet, "A106")
    required_footnote_tokens = (
        "total inventories are for the end of the period",
        "Estimates are not adjusted for price changes.",
        "U.S. Census Bureau",
        "Manufacturers’ Shipments, Inventories, and Orders (M3) Survey",
    )
    if any(token not in footnote for token in required_footnote_tokens):
        fail("M3 full stock-time, valuation, or source note is incomplete")
    year, month = _reference_parts(reference_period)
    if f"{MONTHS[month - 1]} Full Report" not in footnote:
        fail("M3 full source note does not bind the reference month")
    expected_label_hash = structure.get("industry_label_vector_sha256")
    if not isinstance(expected_label_hash, str):
        fail("M3 full label fingerprint is missing")
    stages = (
        ("materials_and_supplies", 0, "A13", "MATERIALS AND SUPPLIES"),
        ("work_in_process", 30, "A43", "WORK IN PROCESS"),
        ("finished_goods", 60, "A73", "FINISHED GOODS"),
    )
    stage_values: dict[str, list[dict[str, Any]]] = {}
    for stage_id, offset, header_cell, header_text in stages:
        _expect_text(sheet, header_cell, header_text)
        labels = [
            _required_display(sheet, f"A{row + offset}")
            for row in M3_FULL_LABEL_ROWS
        ]
        if _profile_vector_hash(labels) != expected_label_hash:
            fail("M3 full industry row universe drifted for " + stage_id)
        rows: list[dict[str, Any]] = []
        for output_index, label_index in enumerate(M3_FULL_DATA_INDEXES):
            row_number = M3_FULL_LABEL_ROWS[label_index] + offset
            row_id = M3_FULL_ROW_IDS[label_index]
            label = labels[label_index]
            if row_id == "electrical_equipment_appliances_and_components":
                label = labels[label_index - 1] + "\n" + label
                row_id = "electrical_equipment_appliances_and_components"
            rows.append(
                {
                    "row_id": row_id,
                    "source_label": label,
                    "source_row": row_number,
                    "seasonally_adjusted": _exact_nonnegative_integer(
                        sheet, f"C{row_number}"
                    ),
                    "not_seasonally_adjusted": _exact_nonnegative_integer(
                        sheet, f"I{row_number}"
                    ),
                    "published_unit": "millions_current_dollars",
                    "stock_time": "end_of_period",
                    "valuation": "not_adjusted_for_price_changes",
                }
            )
        if len(rows) != 24 or len({row["row_id"] for row in rows}) != 24:
            fail("M3 full row universe is not exactly 24 industries")
        stage_values[stage_id] = rows
    combined: list[dict[str, Any]] = []
    for index, row_id in enumerate(row["row_id"] for row in stage_values[stages[0][0]]):
        components = {
            stage_id: stage_values[stage_id][index]
            for stage_id, _, _, _ in stages
        }
        if any(component["row_id"] != row_id for component in components.values()):
            fail("M3 full stage row axes do not align")
        sa_total = sum(
            component["seasonally_adjusted"] for component in components.values()
        )
        nsa_total = sum(
            component["not_seasonally_adjusted"]
            for component in components.values()
        )
        combined.append(
            {
                "row_id": row_id,
                "source_label": components["materials_and_supplies"]["source_label"],
                "materials_and_supplies": {
                    "seasonally_adjusted": components["materials_and_supplies"][
                        "seasonally_adjusted"
                    ],
                    "not_seasonally_adjusted": components[
                        "materials_and_supplies"
                    ]["not_seasonally_adjusted"],
                },
                "work_in_process": {
                    "seasonally_adjusted": components["work_in_process"][
                        "seasonally_adjusted"
                    ],
                    "not_seasonally_adjusted": components["work_in_process"][
                        "not_seasonally_adjusted"
                    ],
                },
                "finished_goods": {
                    "seasonally_adjusted": components["finished_goods"][
                        "seasonally_adjusted"
                    ],
                    "not_seasonally_adjusted": components["finished_goods"][
                        "not_seasonally_adjusted"
                    ],
                },
                "total": {
                    "seasonally_adjusted": sa_total,
                    "not_seasonally_adjusted": nsa_total,
                    "published_in_table_6": False,
                    "derivation": "exact_sum_of_three_published_stage_cells",
                },
            }
        )
    return {
        "reference_period": reference_period,
        "selected_sheet": "Table 6",
        "published_stage_count": 3,
        "published_industry_row_count_per_stage": 24,
        "derived_total_is_not_a_published_table6_cell": True,
        "stock_time_evidenced_in_workbook": True,
        "valuation_evidenced_in_workbook": True,
        "rows": combined,
        "selected_semantic_sha256": sha256_bytes(canonical_json_bytes(combined)),
        "workbook": _workbook_record(workbook, ("Table 6",)),
    }


def _m3_advance_header(sheet: Sheet, reference_period: str) -> None:
    year, month = _reference_parts(reference_period)
    previous_year, previous_month = _previous_month(year, month)
    expected = {
        "C47": "Seasonally Adjusted",
        "I47": "Not Seasonally Adjusted ",
        "C48": "Monthly",
        "F48": "Percent Change",
        "I48": "Monthly",
        "L48": "Percent Change",
        "A49": "Industry",
        "C50": M3_MONTHS_ADVANCE[month - 1],
        "D50": M3_MONTHS_ADVANCE[previous_month - 1],
        "E50": M3_MONTHS_ADVANCE[month - 1],
        "C51": str(year) + "p",
        "D51": str(previous_year) + "r",
        "I50": M3_MONTHS_ADVANCE[month - 1],
        "J50": M3_MONTHS_ADVANCE[previous_month - 1],
        "K50": M3_MONTHS_ADVANCE[month - 1],
        "I51": str(year) + "p",
        "J51": str(previous_year) + "r",
    }
    for reference, text in expected.items():
        _expect_text(sheet, reference, text)
    for reference, text in {
        "E51": str(year - 1),
        "K51": str(year - 1),
    }.items():
        _expect_numeric_text(sheet, reference, text)


def _parse_m3_advance(
    workbook: Workbook,
    structure: Mapping[str, Any],
    reference_period: str,
) -> dict[str, Any]:
    _assert_sheet_topology(workbook, structure)
    sheet = workbook.sheets.get("Total mfg")
    if sheet is None:
        fail("M3 advance workbook lacks the exact Total mfg sheet")
    _expect_text(sheet, "A44", "Table 2.  Total Manufacturers' Inventories")
    _expect_text(
        sheet,
        "A46",
        "[Estimates are shown in millions of dollars and are based on data "
        "from the Manufacturers' Shipments, Inventories, and Orders Survey.]  ",
    )
    _m3_advance_header(sheet, reference_period)
    labels = [_required_display(sheet, f"A{row}") for row in M3_ADVANCE_ROWS]
    if _profile_vector_hash(labels) != structure.get("industry_label_vector_sha256"):
        fail("M3 advance Table 2 row universe drifted")
    rows: list[dict[str, Any]] = []
    for row_id, row_number, label in zip(
        M3_ADVANCE_ROW_IDS, M3_ADVANCE_ROWS, labels
    ):
        rows.append(
            {
                "row_id": row_id,
                "source_label": label,
                "source_row": row_number,
                "seasonally_adjusted": _exact_nonnegative_integer(
                    sheet, f"C{row_number}"
                ),
                "not_seasonally_adjusted": _exact_nonnegative_integer(
                    sheet, f"I{row_number}"
                ),
                "published_unit": "millions_current_dollars",
                "selector_selected": row_id == "all_manufacturing",
            }
        )
    note = _required_display(sheet, "A83")
    year, month = _reference_parts(reference_period)
    if (
        "U.S. Census Bureau" not in note
        or f"{MONTHS[month - 1]} Advance Report" not in note
    ):
        fail("M3 advance source note does not bind the reference month")
    selected = rows[0]
    return {
        "reference_period": reference_period,
        "selected_sheet": "Total mfg",
        "selected_table": "Table 2",
        "published_row_count": 14,
        "selector_selected_row": selected,
        "published_rows": rows,
        "stock_time_evidenced_in_workbook": False,
        "valuation_not_adjusted_for_price_changes_evidenced_in_workbook": False,
        "selector_metadata_complete": False,
        "selected_semantic_sha256": sha256_bytes(canonical_json_bytes(rows)),
        "workbook": _workbook_record(workbook, ("Total mfg",)),
    }


def _mrts_header_text(year: int, month: int, preliminary: bool) -> str:
    display = M3_MONTHS_FULL[month - 1] + " " + str(year)
    return display + ("(p)" if preliminary else "")


def _parse_mrts(
    workbook: Workbook,
    structure: Mapping[str, Any],
    reference_period: str,
) -> dict[str, Any]:
    _assert_sheet_topology(workbook, structure)
    year, month = _reference_parts(reference_period)
    sheet_name = str(year)
    sheet = workbook.sheets.get(sheet_name)
    if sheet is None:
        fail("MRTS workbook lacks the reference-year sheet")
    _expect_text(
        sheet,
        "A1",
        "Estimates of End-of-Month Retail Inventories and Inventories/Sales "
        f"Ratios by Kind of Business: {year}",
    )
    _expect_text(
        sheet,
        "A2",
        "[Estimates are shown in millions of dollars and are based on data "
        "from the Monthly Retail Trade Survey, Annual Retail Trade Survey, "
        "and administrative records]",
    )
    _expect_text(sheet, "A4", "NAICS  Code")
    _expect_text(sheet, "B4", "Kind of Business")
    for current_month in range(1, month + 1):
        column = excel_column_letters(current_month + 2)
        _expect_text(
            sheet,
            column + "5",
            _mrts_header_text(year, current_month, current_month == month),
        )
    for current_month in range(month + 1, 17):
        column = excel_column_letters(current_month + 2)
        _expect_absent_value(sheet, column + "5")
    blocks = (
        (
            "not_adjusted_inventory",
            6,
            "NOT ADJUSTED",
            "inventory",
            "not_adjusted",
        ),
        (
            "adjusted_inventory",
            16,
            "ADJUSTED(1)",
            "inventory",
            "seasonally_and_trading_day_adjusted",
        ),
        (
            "not_adjusted_ratio",
            26,
            "INVENTORIES/SALES, RATIOS NOT ADJUSTED",
            "inventory_sales_ratio",
            "not_adjusted",
        ),
        (
            "adjusted_ratio",
            36,
            "INVENTORIES/SALES, RATIOS ADJUSTED(1)",
            "inventory_sales_ratio",
            "seasonally_and_trading_day_adjusted",
        ),
    )
    inventory_hash = structure.get("inventory_row_vector_sha256")
    ratio_hash = structure.get("ratio_row_vector_sha256")
    output_blocks: dict[str, list[dict[str, Any]]] = {}
    target_column = excel_column_letters(month + 2)
    for block_id, header_row, header, metric, adjustment in blocks:
        _expect_text(sheet, f"B{header_row}", header)
        row_pairs = [
            [
                _required_display(sheet, f"A{row}"),
                _required_display(sheet, f"B{row}"),
            ]
            for row in range(header_row + 1, header_row + 10)
        ]
        expected_hash = inventory_hash if metric == "inventory" else ratio_hash
        if _profile_vector_hash(row_pairs) != expected_hash:
            fail("MRTS full kind-of-business row universe drifted in " + block_id)
        rows: list[dict[str, Any]] = []
        for offset, (row_id, source_pair) in enumerate(
            zip(MRTS_ROW_IDS, row_pairs), start=1
        ):
            row_number = header_row + offset
            for current_month in range(1, month + 1):
                column = excel_column_letters(current_month + 2)
                if metric == "inventory":
                    _exact_nonnegative_integer(sheet, f"{column}{row_number}")
                else:
                    _exact_ratio(sheet, f"{column}{row_number}")
            for current_month in range(month + 1, 17):
                column = excel_column_letters(current_month + 2)
                _expect_absent_value(sheet, f"{column}{row_number}")
            value: int | str
            value_type: str
            unit: str
            if metric == "inventory":
                value = _exact_nonnegative_integer(
                    sheet, f"{target_column}{row_number}"
                )
                value_type = "exact_integer"
                unit = "millions_current_dollars"
            else:
                value = _exact_ratio(sheet, f"{target_column}{row_number}")
                value_type = "canonical_exact_decimal_string"
                unit = "ratio_units"
            rows.append(
                {
                    "row_id": row_id,
                    "naics_display": source_pair[0],
                    "source_label": source_pair[1],
                    "source_row": row_number,
                    "metric": metric,
                    "adjustment_state": adjustment,
                    "value": value,
                    "value_type": value_type,
                    "unit": unit,
                    "stock_time": "end_of_month",
                    "valuation": "not_adjusted_for_price_changes",
                }
            )
        output_blocks[block_id] = rows
    note = _required_display(sheet, "A49")
    if (
        "adjusted for seasonal variation and trading-day differences" not in note
        or "Estimates are not adjusted for price changes." not in note
    ):
        fail("MRTS adjustment or valuation note drifted")
    if "Estimates exclude food services." not in _required_display(sheet, "A51"):
        fail("MRTS inventory-scope note drifted")
    semantic = {
        "reference_period": reference_period,
        "blocks": output_blocks,
    }
    return {
        "reference_period": reference_period,
        "selected_sheet": sheet_name,
        "kind_of_business_row_count": 9,
        "metrics": ["inventory", "inventory_sales_ratio"],
        "adjustment_states": [
            "not_adjusted",
            "seasonally_and_trading_day_adjusted",
        ],
        "geography_selector": "US",
        "geography_explicit_in_workbook": False,
        "stock_time_evidenced_in_workbook": True,
        "valuation_evidenced_in_workbook": True,
        "blocks": output_blocks,
        "selected_semantic_sha256": sha256_bytes(canonical_json_bytes(semantic)),
        "workbook": _workbook_record(workbook, (sheet_name,)),
    }


def _mwts_title(
    adjustment: str,
    metric: str,
    year: int,
    month: int,
) -> str:
    table = "1" if adjustment == "adjusted" else "2"
    adjusted_text = "Adjusted1" if adjustment == "adjusted" else "Not Adjusted"
    metric_text = (
        "Inventories"
        if metric == "inventory"
        else (
            "Inventories to Sales Ratios"
            if adjustment == "adjusted"
            else "Inventories to Sales ratios"
        )
    )
    suffix = "b" if metric == "inventory" else "c"
    return (
        f"Table {table}{suffix}. Revised ({adjusted_text}) Estimates of Monthly "
        f"{metric_text} of Merchant Wholesalers, Except Manufacturers' Sales "
        f"Branches and Offices: January 1992 Through {MONTHS[month - 1]} {year}."
    )


def _validate_mwts_sheet(
    sheet: Sheet,
    structure: Mapping[str, Any],
    reference_period: str,
    adjustment: str,
    metric: str,
) -> tuple[list[dict[str, Any]], str]:
    year, month = _reference_parts(reference_period)
    _expect_text(sheet, "A1", _mwts_title(adjustment, metric, year, month))
    if metric == "inventory":
        expected_unit = (
            "Inventories estimates are in millions of dollars.  Estimates "
            "are based on data from the Monthly Wholesale Trade Survey, and "
            "have been benchmarked using the results of the Annual Wholesale "
            "Trade Survey."
            if adjustment == "adjusted"
            else "Inventories estimates are in millions of dollars. Estimates "
            "are based on data from the Monthly Wholesale Trade Survey, and "
            "have been benchmarked using the results of the Annual Wholesale "
            "Trade Survey."
        )
    else:
        expected_unit = (
            "Ratios are in units. Estimates are based on data from the Monthly "
            "Wholesale Trade Survey, and have been benchmarked using the "
            "results of the Annual Wholesale Trade Survey."
        )
    _expect_text(sheet, "A3", expected_unit)
    if adjustment == "adjusted":
        note = _required_display(sheet, "A7")
        if metric == "inventory":
            required = (
                "inventories estimates are adjusted for seasonal variation",
                "adjusted for trading day differences",
                "not for price changes",
            )
        else:
            required = (
                "sales and inventories estimates are adjusted for seasonal variation",
                "inventories are also adjusted for trading day differences",
                "Estimates are not adjusted for price changes",
            )
        if any(token not in note for token in required):
            fail("adjusted MWTS semantic note drifted")
    _expect_text(sheet, "A17", "Month")
    _expect_text(sheet, "B17", "Year")
    headers = [_required_display(sheet, f"{column}17") for column in (
        excel_column_letters(index) for index in range(3, 25)
    )]
    descriptions = [_required_display(sheet, f"{column}16") for column in (
        excel_column_letters(index) for index in range(3, 25)
    )]
    if _profile_vector_hash(headers) != structure.get("naics_vector_sha256"):
        fail("MWTS exact NAICS header universe drifted")
    if _profile_vector_hash(descriptions) != structure.get(
        "description_vector_sha256"
    ):
        fail("MWTS exact description universe drifted")
    expected_axis = list(reversed(_month_axis("1992-01", reference_period)))
    semantic_digest = hashlib.sha256()
    semantic_digest.update(b"beforeit-us-census-mwts-selected-sheet.v1\0")
    target_rows: list[dict[str, Any]] = []
    for offset, (period_year, period_month) in enumerate(expected_axis):
        row_number = 18 + offset
        month_text = MONTHS[period_month - 1]
        if offset == 0:
            month_text += " \u00a0 p"
        elif offset == 1 or (adjustment == "adjusted" and offset == 12):
            month_text += " \u00a0 r"
        _expect_text(sheet, f"A{row_number}", month_text)
        year_cell = _required_cell(sheet, f"B{row_number}")
        if (
            year_cell.cell_type != "n"
            or year_cell.raw_value != str(period_year)
        ):
            fail("MWTS period year axis drifted")
        for column_number, (row_id, code, description) in enumerate(
            zip(MWTS_ROW_IDS, headers, descriptions), start=3
        ):
            reference = excel_column_letters(column_number) + str(row_number)
            cell = _required_cell(sheet, reference)
            if cell.cell_type == "s" and cell.value == "NA":
                status = "SOURCE_NOT_AVAILABLE"
                canonical_value = "NA"
            elif metric == "inventory":
                status = "EXACT_INTEGER"
                canonical_value = str(_exact_nonnegative_integer(sheet, reference))
            else:
                status = "EXACT_DECIMAL_RATIO"
                canonical_value = _exact_ratio(sheet, reference)
            semantic_digest.update(
                (
                    f"{period_year:04d}-{period_month:02d}\0{code}\0{status}\0"
                    + canonical_value
                    + "\n"
                ).encode("utf-8")
            )
            if offset == 0:
                if status == "SOURCE_NOT_AVAILABLE":
                    fail("MWTS target row contains a not-available value")
                value: int | str
                value_type: str
                if metric == "inventory":
                    value = int(canonical_value)
                    value_type = "exact_integer"
                else:
                    value = canonical_value
                    value_type = "canonical_exact_decimal_string"
                target_rows.append(
                    {
                        "row_id": row_id,
                        "naics_display": code,
                        "source_description": description,
                        "source_column": excel_column_letters(column_number),
                        "value": value,
                        "value_type": value_type,
                        "unit": (
                            "millions_current_dollars"
                            if metric == "inventory"
                            else "ratio_units"
                        ),
                    }
                )
    last_expected_row = 17 + len(expected_axis)
    for (row_number, column_number), cell in sheet.cells.items():
        if row_number > last_expected_row and 1 <= column_number <= 24:
            if cell.value is not None:
                fail("MWTS sheet contains a period row beyond January 1992")
    return target_rows, semantic_digest.hexdigest()


def _parse_mwts(
    workbook: Workbook,
    structure: Mapping[str, Any],
    reference_period: str,
    adjustment: str,
) -> dict[str, Any]:
    _assert_sheet_topology(workbook, structure)
    inventory_sheet = workbook.sheets.get("Inventories")
    ratio_sheet = workbook.sheets.get("Inventories to Sales Ratios")
    if inventory_sheet is None or ratio_sheet is None:
        fail("MWTS workbook lacks an exact selected sheet")
    inventory_rows, inventory_grid_hash = _validate_mwts_sheet(
        inventory_sheet,
        structure,
        reference_period,
        adjustment,
        "inventory",
    )
    ratio_rows, ratio_grid_hash = _validate_mwts_sheet(
        ratio_sheet,
        structure,
        reference_period,
        adjustment,
        "inventory_sales_ratio",
    )
    if [row["row_id"] for row in inventory_rows] != [
        row["row_id"] for row in ratio_rows
    ]:
        fail("MWTS inventory and ratio row universes do not align")
    rows = []
    for inventory, ratio in zip(inventory_rows, ratio_rows):
        rows.append(
            {
                "row_id": inventory["row_id"],
                "naics_display": inventory["naics_display"],
                "source_description": inventory["source_description"],
                "source_column": inventory["source_column"],
                "inventory": inventory["value"],
                "inventory_value_type": inventory["value_type"],
                "inventory_unit": "millions_current_dollars",
                "inventory_sales_ratio": ratio["value"],
                "ratio_value_type": ratio["value_type"],
                "ratio_unit": "ratio_units",
                "stock_time": "end_of_month",
                "adjustment_state": (
                    "seasonally_and_trading_day_adjusted"
                    if adjustment == "adjusted"
                    else "not_adjusted"
                ),
            }
        )
    valuation_evidenced = adjustment == "adjusted"
    return {
        "reference_period": reference_period,
        "selected_sheets": ["Inventories", "Inventories to Sales Ratios"],
        "kind_of_business_row_count": 22,
        "geography_selector": "US",
        "geography_explicit_in_workbook": False,
        "stock_time_semantics": "end_of_month",
        "adjustment_state": (
            "seasonally_and_trading_day_adjusted"
            if adjustment == "adjusted"
            else "not_adjusted"
        ),
        "valuation_not_adjusted_for_price_changes_evidenced_in_workbook": (
            valuation_evidenced
        ),
        "selector_metadata_complete": valuation_evidenced,
        "rows": rows,
        "inventory_history_semantic_sha256": inventory_grid_hash,
        "ratio_history_semantic_sha256": ratio_grid_hash,
        "selected_semantic_sha256": sha256_bytes(canonical_json_bytes(rows)),
        "workbook": _workbook_record(
            workbook, ("Inventories", "Inventories to Sales Ratios")
        ),
    }


def _binding_semantic_hash(document: Mapping[str, Any]) -> str:
    copy = parse_json_bytes(canonical_json_bytes(document), "binding copy")
    artifact = copy.get("artifact")
    if not isinstance(artifact, dict) or "content_sha256" not in artifact:
        fail("binding content hash field is missing")
    del artifact["content_sha256"]
    return sha256_bytes(canonical_json_bytes(copy))


def _load_planned_binding(
    path: Path,
    profile: Mapping[str, Any],
) -> dict[str, Any]:
    data = _read_pinned_regular_file(path, "local binding")
    binding = parse_json_bytes(data, "local binding")
    if set(binding) != {"artifact", "records"}:
        fail("local binding top-level keys drifted")
    artifact = binding["artifact"]
    if not isinstance(artifact, dict) or set(artifact) != {
        "schema_version",
        "status",
        "role",
        "canonicalization",
        "profile_content_sha256",
        "prospective_contract_sha256",
        "content_sha256",
    }:
        fail("local binding artifact block drifted")
    profile_sha = profile["artifact"]["content_sha256"]
    if (
        artifact["schema_version"] != BINDING_SCHEMA_VERSION
        or artifact["status"] != STATUS
        or artifact["role"] != "UNAUTHENTICATED_LOCAL_CAPTURE_BINDING_NONADMITTING"
        or artifact["canonicalization"] != CANONICALIZATION
        or artifact["profile_content_sha256"] != profile_sha
        or artifact["prospective_contract_sha256"]
        != EXPECTED_CONTRACT_PHYSICAL_SHA256
        or not _is_sha256_text(artifact["content_sha256"])
        or _binding_semantic_hash(binding) != artifact["content_sha256"]
    ):
        fail("local binding artifact identity or ceiling drifted")
    records = binding["records"]
    if not isinstance(records, list) or len(records) != 5:
        fail("local binding must contain exactly five records")
    expected_keys = {
        "profile_id",
        "requirement_id",
        "event_id",
        "reference_period",
        "scheduled_timestamp_utc",
        "capture_deadline_utc",
        "source_url",
        "effective_url",
        "http_status",
        "content_type",
        "raw_sha256",
        "raw_byte_count",
        "retrieved_at_utc",
        "claim",
    }
    for index, (profile_id, record) in enumerate(
        zip(EXPECTED_PROFILE_IDS, records), start=1
    ):
        location = "local binding record " + str(index)
        if not isinstance(record, dict) or set(record) != expected_keys:
            fail(location + " keys drifted")
        expected = EXPECTED_BINDINGS[profile_id]
        for key in (
            "profile_id",
            "requirement_id",
            "event_id",
            "reference_period",
            "scheduled_timestamp_utc",
            "capture_deadline_utc",
            "source_url",
        ):
            expected_value = profile_id if key == "profile_id" else expected[key]
            if record[key] != expected_value:
                fail(location + "." + key + " drifted")
        if (
            record["effective_url"] != expected["source_url"]
            or type(record["http_status"]) is not int
            or record["http_status"] != 200
            or record["content_type"]
            != "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            or record["claim"]
            != "CALLER_ASSERTED_LOCAL_INTEGRITY_NOT_PROVIDER_AUTHENTICATION"
        ):
            fail(location + " response metadata drifted")
        raw_hash = record["raw_sha256"]
        if not _is_sha256_text(raw_hash):
            fail(location + " raw SHA-256 is malformed")
        _required_exact_int(record, "raw_byte_count", location)
        retrieved_at = record["retrieved_at_utc"]
        if not _is_utc_timestamp(retrieved_at):
            fail(location + " retrieval timestamp is malformed")
        if not (
            expected["scheduled_timestamp_utc"]
            <= retrieved_at
            <= expected["capture_deadline_utc"]
        ):
            fail(location + " retrieval timestamp lies outside the event window")
    return binding


def _snapshot_paths(paths: Mapping[str, Path]) -> dict[str, Path]:
    if not isinstance(paths, Mapping) or set(paths) != set(EXPECTED_PROFILE_IDS):
        fail("external workbook mapping must contain the exact five profiles")
    snapshot: dict[str, Path] = {}
    identities: set[tuple[int, int]] = set()
    for profile_id in EXPECTED_PROFILE_IDS:
        path = paths[profile_id]
        if not isinstance(path, Path) or not path.is_absolute():
            fail(profile_id + " workbook path must be an absolute Path")
        supplied = Path(os.fspath(path))
        absolute = Path(os.path.abspath(os.fspath(path)))
        if supplied != absolute:
            fail(profile_id + " workbook path must use canonical absolute spelling")
        try:
            resolved = absolute.resolve(strict=True)
            metadata = os.stat(absolute, follow_symlinks=False)
        except OSError as error:
            raise ProfileError(profile_id + " workbook path is unavailable") from error
        if resolved != absolute or not stat.S_ISREG(metadata.st_mode):
            fail(profile_id + " workbook path is unsafe")
        identity = (metadata.st_dev, metadata.st_ino)
        if identity in identities:
            fail("two profiles resolve to the same external workbook")
        identities.add(identity)
        snapshot[profile_id] = absolute
    return snapshot


def _parse_profile_workbook(
    workbook: Workbook,
    profile_record: Mapping[str, Any],
    structure: Mapping[str, Any],
    reference_period: str,
) -> dict[str, Any]:
    parser_kind = profile_record["parser_kind"]
    if parser_kind == "m3_full_table6":
        return _parse_m3_full(workbook, structure, reference_period)
    if parser_kind == "m3_advance_total":
        return _parse_m3_advance(workbook, structure, reference_period)
    if parser_kind == "mrts":
        return _parse_mrts(workbook, structure, reference_period)
    if parser_kind == "mwts_adjusted":
        return _parse_mwts(workbook, structure, reference_period, "adjusted")
    if parser_kind == "mwts_not_adjusted":
        return _parse_mwts(
            workbook, structure, reference_period, "not_adjusted"
        )
    fail("profile parser kind is unsupported")


def _finalize_result(result: dict[str, Any]) -> dict[str, Any]:
    if "content_sha256" in result:
        fail("result was already finalized")
    result["content_sha256"] = sha256_bytes(canonical_json_bytes(result))
    return result


def _build_bundle(
    paths: Mapping[str, Path],
    mode: str,
    binding: Mapping[str, Any] | None,
) -> dict[str, Any]:
    profile, _ = _load_profile_and_contract()
    safe_paths = _snapshot_paths(paths)
    records_by_id = {
        record["profile_id"]: record for record in profile["profiles"]
    }
    binding_records: dict[str, Mapping[str, Any]] = {}
    if mode == "planned_local_binding":
        if binding is None:
            fail("planned parsing requires the exact local binding")
        binding_records = {
            record["profile_id"]: record for record in binding["records"]
        }
        source_verification_kind = (
            "SELF_HASHED_CALLER_BINDING_PLUS_EXACT_BODY_HASH_NONAUTHENTICATING"
        )
        binding_sha = binding["artifact"]["content_sha256"]
    elif mode == "observed_current":
        if binding is not None:
            fail("observed-current parsing does not accept a caller binding")
        source_verification_kind = (
            "FROZEN_PRESENT_DAY_DIAGNOSTIC_SHA_SIZE_PINS_NONAUTHENTICATING"
        )
        binding_sha = None
    else:
        fail("bundle mode is unsupported")
    output_records: list[dict[str, Any]] = []
    seen_hashes: set[str] = set()
    for profile_id in EXPECTED_PROFILE_IDS:
        profile_record = records_by_id[profile_id]
        workbook = parse_workbook(safe_paths[profile_id])
        if workbook.raw_sha256 in seen_hashes:
            fail("two profile workbooks have identical raw bytes")
        seen_hashes.add(workbook.raw_sha256)
        if mode == "planned_local_binding":
            source_record = binding_records[profile_id]
            reference_period = profile_record["reference_period"]
        else:
            source_record = profile_record["observed_current"]
            reference_period = source_record["reference_period"]
        if (
            workbook.raw_sha256 != source_record["raw_sha256"]
            or workbook.raw_byte_count != source_record["raw_byte_count"]
        ):
            fail(profile_id + " external body differs from its mandatory source pin")
        structure = profile["structures"][profile_record["parser_kind"]]
        parsed = _parse_profile_workbook(
            workbook,
            profile_record,
            structure,
            reference_period,
        )
        output_records.append(
            {
                "profile_id": profile_id,
                "requirement_id": profile_record["requirement_id"],
                "event_id": profile_record["event_id"],
                "planned_reference_period": profile_record["reference_period"],
                "parsed_reference_period": reference_period,
                "scheduled_timestamp_utc": profile_record[
                    "scheduled_timestamp_utc"
                ],
                "capture_deadline_utc": profile_record["capture_deadline_utc"],
                "source_url": profile_record["source_url"],
                "selector": profile_record["selector"],
                "source_body_hash_and_size_verified": True,
                "declared_source_url_contract_binding_verified": True,
                "caller_binding_url_fields_validated": (
                    mode == "planned_local_binding"
                ),
                "body_to_declared_url_provenance_verified": False,
                "provider_provenance_verified": False,
                "future_compatibility_claimed": False,
                "parsed": parsed,
                "gates": hard_false_gates(),
            }
        )
    result = {
        "schema_version": SCHEMA_VERSION,
        "generator_version": GENERATOR_VERSION,
        "status": STATUS,
        "role": ROLE,
        "mode": mode,
        "canonicalization": CANONICALIZATION,
        "profile_content_sha256": profile["artifact"]["content_sha256"],
        "profile_physical_sha256": EXPECTED_PROFILE_PHYSICAL_SHA256,
        "prospective_contract_physical_sha256": (
            EXPECTED_CONTRACT_PHYSICAL_SHA256
        ),
        "local_binding_content_sha256": binding_sha,
        "profile_count": len(output_records),
        "full_five_profile_topology_verified": len(output_records) == 5,
        "source_verification_performed": True,
        "source_verification_kind": source_verification_kind,
        "current_schema_is_not_future_compatibility_evidence": True,
        "local_binding_is_not_provider_authentication": True,
        "origin_evidence_claimed": False,
        "self_accepted": False,
        "independent_audit_required": True,
        "records": output_records,
        "gates": hard_false_gates(),
    }
    return _finalize_result(result)


def parse_observed_current_bundle(paths: Mapping[str, Path]) -> dict[str, Any]:
    """Parse the five frozen current bodies as diagnostics, never as origin."""

    return _build_bundle(paths, "observed_current", None)


def parse_planned_local_bundle(
    paths: Mapping[str, Path],
    binding_path: Path,
) -> dict[str, Any]:
    """Parse five future local candidates with mandatory local hash binding."""

    profile, _ = _load_profile_and_contract()
    binding = _load_planned_binding(binding_path, profile)
    return _build_bundle(paths, "planned_local_binding", binding)


def _validate_result_document(result: Mapping[str, Any]) -> None:
    if result.get("status") != STATUS or result.get("role") != ROLE:
        fail("result ceiling drifted")
    if result.get("profile_count") != 5 or result.get(
        "full_five_profile_topology_verified"
    ) is not True:
        fail("result topology drifted")
    if result.get("source_verification_performed") is not True:
        fail("result falsely omits mandatory source verification")
    if result.get("origin_evidence_claimed") is not False:
        fail("result falsely claims origin evidence")
    if result.get("self_accepted") is not False:
        fail("result falsely self-accepts")
    if result.get("gates") != hard_false_gates():
        fail("result top-level gates drifted")
    records = result.get("records")
    if not isinstance(records, list) or [
        record.get("profile_id") if isinstance(record, dict) else None
        for record in records
    ] != list(EXPECTED_PROFILE_IDS):
        fail("result profile order drifted")
    for record in records:
        if record.get("gates") != hard_false_gates():
            fail("result record gates drifted")
        if record.get("source_body_hash_and_size_verified") is not True:
            fail("result record omits local body fixity verification")
        if record.get("declared_source_url_contract_binding_verified") is not True:
            fail("result record contract URL declaration drifted")
        if record.get("caller_binding_url_fields_validated") is not (
            result.get("mode") == "planned_local_binding"
        ):
            fail("result record caller URL-field validation drifted")
        if record.get("body_to_declared_url_provenance_verified") is not False:
            fail("result record falsely binds local bytes to the declared URL")
        if record.get("provider_provenance_verified") is not False:
            fail("result record falsely claims provider provenance")
        if record.get("future_compatibility_claimed") is not False:
            fail("result record falsely claims future compatibility")
    content_hash = result.get("content_sha256")
    if not _is_sha256_text(content_hash):
        fail("result content hash is malformed")
    copy = parse_json_bytes(canonical_json_bytes(result), "result copy")
    del copy["content_sha256"]
    if sha256_bytes(canonical_json_bytes(copy)) != content_hash:
        fail("result content hash does not verify")


def validate_observed_result_bytes(
    result_bytes: bytes,
    paths: Mapping[str, Path],
) -> dict[str, Any]:
    """Rebuild an observed diagnostic and compare it type-exactly."""

    result = parse_json_bytes(result_bytes, "observed result")
    _validate_result_document(result)
    rebuilt = parse_observed_current_bundle(paths)
    if canonical_json_bytes(result) != canonical_json_bytes(rebuilt):
        fail("observed result does not exactly replay from source bytes")
    return result


def validate_planned_result_bytes(
    result_bytes: bytes,
    paths: Mapping[str, Path],
    binding_path: Path,
) -> dict[str, Any]:
    """Rebuild a planned local diagnostic and compare it type-exactly."""

    result = parse_json_bytes(result_bytes, "planned result")
    _validate_result_document(result)
    rebuilt = parse_planned_local_bundle(paths, binding_path)
    if canonical_json_bytes(result) != canonical_json_bytes(rebuilt):
        fail("planned result does not exactly replay from source bytes")
    return result


def _cli_paths(arguments: argparse.Namespace) -> dict[str, Path]:
    return {
        "m3_2026_08_stage_table": Path(arguments.m3_full),
        "mwts_2026_08_adjusted_inventory": Path(arguments.mwts_adjusted),
        "mwts_2026_08_not_adjusted_inventory": Path(arguments.mwts_not_adjusted),
        "mrts_2026_08_inventory": Path(arguments.mrts),
        "m3_2026_09_advance_total": Path(arguments.m3_advance),
    }


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        required=True,
        choices=("observed-current", "planned-local-binding"),
    )
    parser.add_argument("--m3-full", required=True)
    parser.add_argument("--mwts-adjusted", required=True)
    parser.add_argument("--mwts-not-adjusted", required=True)
    parser.add_argument("--mrts", required=True)
    parser.add_argument("--m3-advance", required=True)
    parser.add_argument("--binding")
    arguments = parser.parse_args(argv)
    paths = _cli_paths(arguments)
    try:
        if arguments.mode == "observed-current":
            if arguments.binding is not None:
                fail("observed-current mode forbids --binding")
            result = parse_observed_current_bundle(paths)
        else:
            if arguments.binding is None:
                fail("planned-local-binding mode requires --binding")
            result = parse_planned_local_bundle(paths, Path(arguments.binding))
    except ProfileError as error:
        print("CANNOT_RUN: " + str(error), file=sys.stderr)
        return 2
    sys.stdout.buffer.write(canonical_json_bytes(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
