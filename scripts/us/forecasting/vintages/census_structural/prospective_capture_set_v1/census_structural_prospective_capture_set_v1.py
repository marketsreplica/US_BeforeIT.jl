#!/usr/bin/env python3
"""Offline Census AIES/SUSB prospective-capture-set mechanics.

This module has no downloader, socket, subprocess, filesystem writer, model,
truth, scoring, inventory, or admission path.  It accepts six complete body
and raw-header byte pairs supplied by a caller, validates their physical
representations, and compiles deterministic nonadmitting capture-set and leaf
candidates.  Injected bytes are never attributed to the planned URLs.
"""

from __future__ import annotations

import csv
from collections import Counter
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import struct
from typing import Any, Mapping, Sequence
import zipfile


SCHEMA_VERSION = "beforeit-us-census-structural-prospective-capture-set.v1"
STATUS = "CANNOT_RUN"
ROLE = "OFFLINE_CENSUS_STRUCTURAL_CAPTURE_SET_AND_LEAF_MECHANICS_NONADMITTING"
CANONICALIZATION = "utf8-sorted-keys-compact-json-lf.v1"
PROFILE_CANONICALIZATION = (
    "utf8-sorted-keys-compact-json-lf.v1-excluding-artifact-content-sha256"
)
MODULE_PATH = Path(os.path.abspath(__file__))
PROFILE_PATH = MODULE_PATH.with_name("census_structural_prospective_capture_set_v1.json")
REPOSITORY_ROOT = MODULE_PATH.parents[6]
EXPECTED_PROFILE_PHYSICAL_SHA256 = (
    "07360fc507c97e76139b8b86a6ce5b4e99b4acf922bdcef2d643727c74f1cc47"
)
EXPECTED_PROFILE_SEMANTIC_SHA256 = (
    "9fe15ba9d598ad454e25d0bc393e791f2a52d016ffcf1d3aefb707ff9d799e38"
)
EMPTY_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
HASH_PATTERN = re.compile(r"\A[0-9a-f]{64}\Z")
HEADER_NAME_PATTERN = re.compile(rb"\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\Z")
HTTP_STATUS_PATTERN = re.compile(rb"\AHTTP/(?:1\.0|1\.1|2|2\.0) 200 ?\Z")
SIGNED_DECIMAL_PATTERN = re.compile(r"\A-?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)\Z")
NONNEGATIVE_INTEGER_PATTERN = re.compile(r"\A(?:0|[1-9][0-9]*)\Z")
TWO_DIGIT_CODE_PATTERN = re.compile(r"\A[0-9]{2}\Z")
UTC_TIMESTAMP_PATTERN = re.compile(r"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z")

# This tuple is deliberately independent of the adjacent profile.  The profile
# is not allowed to choose what authorizes it.  No pinned Python/Julia module is
# imported or executed by this module; transport/recovery remains outside this
# offline artifact.
EXPECTED_SOURCE_PINS = (
    ("logical_module_v1", "scripts/us/forecasting/vintages/census_structural/profile_v1/USCensusStructuralProfileV1.jl", "e0a683586a44d0cba8129d7494c49e00e1606453c46e94b37f60d4804f450f68"),
    ("logical_profile_v1", "scripts/us/forecasting/vintages/census_structural/profile_v1/census_structural_profile_v1.toml", "512b35c1d80c9d6c8b387cdd68affd4a1ae92b1dc040c04aacae8545b47ef157"),
    ("logical_tests_v1", "scripts/us/forecasting/vintages/census_structural/profile_v1/test_census_structural_profile_v1.jl", "ef2089d3fb47400947111f8b8a743999c42c0092b547d70e8be7c9708447cd55"),
    ("logical_readme_v1", "scripts/us/forecasting/vintages/census_structural/profile_v1/README.md", "4a734c3fe7239dc686b9fe0de53075ec5a4d0c3b96d31298c2be3d8d45a980e5"),
    ("physical_module_v1", "scripts/us/forecasting/vintages/census_structural/present_day_physical_profile_v1/census_structural_present_day_physical_profile_v1.py", "4dbfdc0f6ab0dc616638160e2cc58f994d232eae9974127c0a28d87ac0f0ac47"),
    ("physical_profile_v1", "scripts/us/forecasting/vintages/census_structural/present_day_physical_profile_v1/census_structural_present_day_physical_profile_v1.json", "556fb4319ddc05779bb785588b32df60704ff4a276f8a133b58cef59710b9673"),
    ("physical_tests_v1", "scripts/us/forecasting/vintages/census_structural/present_day_physical_profile_v1/test_census_structural_present_day_physical_profile_v1.py", "5e70698c77fce350ded4989a62a65acd5c7b61d1b0b51e6f4421a74317aae4b6"),
    ("physical_readme_v1", "scripts/us/forecasting/vintages/census_structural/present_day_physical_profile_v1/README.md", "8931ca12e6ccc9424c8b496bd3ef9ae30517e79227080ff6fea7f909e6b5a611"),
    ("prospective_v2_module", "scripts/us/forecasting/vintages/prospective/USProspectiveAcquisitionContractV2.jl", "435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379"),
    ("prospective_v2_contract", "scripts/us/forecasting/vintages/prospective/prospective_2026q3_contract_v2.toml", "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"),
    ("common_origin_v3_module", "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/USCommonOriginAcquisitionV3.jl", "9654eb61b92b2655391b00952ed4cbee0e9fa58224339f1fb0440c51570e719e"),
    ("common_origin_v3_policy", "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/common_origin_acquisition_v3_policy.toml", "0deff5e3e6c950b5682bba96fcefa1fa2304bbbadae6227a940376dc7699bd3e"),
    ("common_origin_v4_module", "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4/USCommonOriginAcquisitionV4.jl", "0f4c248950ebee59d1e6b5882db6516cbb539f9e54c7dfbb6b53fe0f7a5f6b4e"),
    ("common_origin_v4_policy", "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4/common_origin_acquisition_v4_policy.toml", "84e74d236f0e0ac781a482b996be95fceefe56f2a349be089b51054c3edd8834"),
    ("current_inventory", "scripts/us/forecasting/vintages/current_inventory.toml", "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae"),
)

HARD_FALSE_GATE_NAMES = (
    "accuracy_claim_allowed",
    "availability_verified",
    "capture_set_complete",
    "custody_verified",
    "external_timestamp_verified",
    "forecast_execution_allowed",
    "inventory_mutation_allowed",
    "model_input_allowed",
    "origin_admissible",
    "owner_validator_decisions_verified",
    "policy_qualified",
    "production_allowed",
    "promotion_allowed",
    "provider_provenance_verified",
    "qualified_leaf",
    "raw_capture_complete",
    "scoring_allowed",
    "supersession_approved",
    "transport_authenticated",
    "truth_access_allowed",
    "verifier_release_authenticated",
)

BASE_BLOCKERS = (
    "NONPROSPECTIVE_PRESENT_DAY_DIAGNOSTIC_BYTES",
    "NO_PROSPECTIVE_CAPTURE_RECEIPT",
    "INJECTED_BYTES_NOT_ATTRIBUTED_TO_PLANNED_URLS",
    "CAPTURE_TIME_POLICY_AND_DOCUMENTATION_RECEIPTS_ABSENT",
    "AIES_FLAG_NOTE_SEMANTICS_UNRESOLVED",
    "LEGACY_TO_CANDIDATE_SUPERSESSION_DECISIONS_UNAPPROVED",
    "AUTHENTICATED_TRANSPORT_EVIDENCE_ABSENT",
    "TWO_EXTERNAL_CUSTODY_DOMAINS_ABSENT",
    "RFC3161_EVIDENCE_ABSENT",
    "OWNER_AND_INDEPENDENT_VALIDATOR_DECISIONS_ABSENT",
    "AUTHENTICATED_VERIFIER_RELEASE_ABSENT",
    "COMMON_ORIGIN_SUCCESSOR_DISPATCH_ABSENT",
)


class CaptureSetError(RuntimeError):
    """Closed failure from the offline profile/compiler."""

    def __init__(self, code: str, detail: str):
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


def fail(code: str, detail: str) -> None:
    raise CaptureSetError(code, detail)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _assert_plain_json(value: Any, location: str = "result") -> None:
    value_type = type(value)
    if value is None or value_type in (str, bool, int):
        return
    if value_type is float:
        if value != value or value in (float("inf"), float("-inf")):
            fail("PROJECTION_SUBJECT_OR_REPLAY_MISMATCH", f"{location} is non-finite")
        return
    if value_type is list:
        for index, item in enumerate(value):
            _assert_plain_json(item, f"{location}[{index}]")
        return
    if value_type is dict:
        for key, item in value.items():
            if type(key) is not str:
                fail("PROJECTION_SUBJECT_OR_REPLAY_MISMATCH", f"{location} has a non-concrete-string key")
            _assert_plain_json(item, f"{location}.{key}")
        return
    fail(
        "PROJECTION_SUBJECT_OR_REPLAY_MISMATCH",
        f"{location} uses forbidden concrete type {value_type.__name__}",
    )


def canonical_json_bytes(value: Any) -> bytes:
    _assert_plain_json(value)
    try:
        text = json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
    except (TypeError, ValueError) as error:
        fail("PROJECTION_SUBJECT_OR_REPLAY_MISMATCH", str(error))
    return (text + "\n").encode("utf-8")


def _duplicate_key(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail("SOURCE_BINDING_MISMATCH", f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def _nonfinite_json(value: str) -> None:
    fail("SOURCE_BINDING_MISMATCH", f"non-finite JSON token {value!r}")


def _parse_json_bytes(raw: bytes, code: str) -> dict[str, Any]:
    if raw.startswith(b"\xef\xbb\xbf"):
        fail(code, "JSON BOM is forbidden")
    try:
        parsed = json.loads(
            raw,
            object_pairs_hook=_duplicate_key,
            parse_constant=_nonfinite_json,
        )
    except CaptureSetError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(code, f"invalid JSON: {error}")
    if type(parsed) is not dict:
        fail(code, "JSON root must be one concrete object")
    return parsed


def _profile_semantic_sha256(profile: Mapping[str, Any]) -> str:
    clone = json.loads(json.dumps(profile, ensure_ascii=False, allow_nan=False))
    artifact = clone.get("artifact")
    if type(artifact) is not dict or "content_sha256" not in artifact:
        fail("SOURCE_BINDING_MISMATCH", "profile semantic hash field is missing")
    del artifact["content_sha256"]
    return sha256_bytes(canonical_json_bytes(clone))


def _hard_false_gates() -> dict[str, bool]:
    return {name: False for name in HARD_FALSE_GATE_NAMES}


def _exact_keys(value: Any, expected: Sequence[str], code: str, location: str) -> dict[str, Any]:
    if type(value) is not dict:
        fail(code, f"{location} must be one concrete object")
    if set(value) != set(expected):
        fail(code, f"{location} key set drifted")
    return value


def _exact_int(value: Any, code: str, location: str, minimum: int = 0) -> int:
    if type(value) is not int or value < minimum:
        fail(code, f"{location} must be an exact integer >= {minimum}")
    return value


def _exact_bool(value: Any, expected: bool, code: str, location: str) -> bool:
    if type(value) is not bool or value is not expected:
        fail(code, f"{location} must be exactly {expected}")
    return value


def _exact_str(value: Any, expected: str, code: str, location: str) -> str:
    if type(value) is not str or value != expected:
        fail(code, f"{location} must be exactly {expected!r}")
    return value


def _safe_read_file(path: Path, maximum_bytes: int, location: str) -> bytes:
    if type(path) is not Path or not path.is_absolute():
        fail("SOURCE_BINDING_MISMATCH", f"{location} must be an absolute Path")
    if Path(os.path.abspath(path)) != path:
        fail("SOURCE_BINDING_MISMATCH", f"{location} is not canonical")
    try:
        if path.resolve(strict=True) != path:
            fail("SOURCE_BINDING_MISMATCH", f"{location} has a symlinked path component")
        path_before = os.stat(path, follow_symlinks=False)
    except OSError as error:
        fail("SOURCE_BINDING_MISMATCH", f"cannot resolve {location}: {error}")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        fail("SOURCE_BINDING_MISMATCH", f"cannot open {location}: {error}")
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_nlink != 1
            or before.st_uid != os.getuid()
            or before.st_mode & 0o022
            or before.st_size < 1
            or before.st_size > maximum_bytes
        ):
            fail("SOURCE_BINDING_MISMATCH", f"{location} is not a safe bounded source")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(1 << 20, maximum_bytes - total + 1))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > maximum_bytes:
                fail("SOURCE_BINDING_MISMATCH", f"{location} exceeds its byte ceiling")
        after = os.fstat(descriptor)
        if (
            before.st_dev,
            before.st_ino,
            before.st_size,
            before.st_mtime_ns,
            before.st_ctime_ns,
        ) != (
            after.st_dev,
            after.st_ino,
            after.st_size,
            after.st_mtime_ns,
            after.st_ctime_ns,
        ):
            fail("SOURCE_BINDING_MISMATCH", f"{location} changed during read")
        try:
            path_after = os.stat(path, follow_symlinks=False)
        except OSError as error:
            fail("SOURCE_BINDING_MISMATCH", f"{location} pathname changed: {error}")
        descriptor_identity = (
            after.st_dev,
            after.st_ino,
            after.st_mode,
            after.st_nlink,
            after.st_uid,
            after.st_gid,
            after.st_size,
            after.st_mtime_ns,
            after.st_ctime_ns,
        )
        if descriptor_identity != (
            path_before.st_dev,
            path_before.st_ino,
            path_before.st_mode,
            path_before.st_nlink,
            path_before.st_uid,
            path_before.st_gid,
            path_before.st_size,
            path_before.st_mtime_ns,
            path_before.st_ctime_ns,
        ) or descriptor_identity != (
            path_after.st_dev,
            path_after.st_ino,
            path_after.st_mode,
            path_after.st_nlink,
            path_after.st_uid,
            path_after.st_gid,
            path_after.st_size,
            path_after.st_mtime_ns,
            path_after.st_ctime_ns,
        ):
            fail("SOURCE_BINDING_MISMATCH", f"{location} pathname identity changed during read")
        raw = b"".join(chunks)
        if len(raw) != before.st_size:
            fail("SOURCE_BINDING_MISMATCH", f"{location} size changed during read")
        return raw
    finally:
        os.close(descriptor)


def _load_and_check_profile() -> dict[str, Any]:
    raw = _safe_read_file(PROFILE_PATH, 2 * 1024 * 1024, "profile")
    if sha256_bytes(raw) != EXPECTED_PROFILE_PHYSICAL_SHA256:
        fail("SOURCE_BINDING_MISMATCH", "profile physical SHA-256 drifted")
    profile = _parse_json_bytes(raw, "SOURCE_BINDING_MISMATCH")
    artifact = _exact_keys(
        profile.get("artifact"),
        ["canonicalization", "content_sha256", "role", "schema_version", "status"],
        "SOURCE_BINDING_MISMATCH",
        "artifact",
    )
    if (
        artifact["schema_version"] != SCHEMA_VERSION
        or artifact["status"] != STATUS
        or artifact["role"] != ROLE
        or artifact["canonicalization"] != PROFILE_CANONICALIZATION
        or artifact["content_sha256"] != EXPECTED_PROFILE_SEMANTIC_SHA256
        or _profile_semantic_sha256(profile) != EXPECTED_PROFILE_SEMANTIC_SHA256
    ):
        fail("SOURCE_BINDING_MISMATCH", "profile identity or claim ceiling drifted")
    if profile.get("gates") != _hard_false_gates():
        fail("SOURCE_BINDING_MISMATCH", "profile gates drifted")
    contract = profile.get("capture_contract")
    if type(contract) is not dict:
        fail("SOURCE_BINDING_MISMATCH", "capture contract is missing")
    for field in (
        "availability_claimed",
        "body_to_url_provenance_claimed",
        "capture_receipt_present",
        "common_origin_v3_integration",
        "common_origin_v4_integration",
        "injected_bytes_are_provider_url_bytes",
        "network_implemented",
        "prospective_capture_performed",
        "provider_authentication_claimed",
        "response_headers_are_authenticated",
        "transport_authentication_claimed",
        "writer_implemented",
    ):
        _exact_bool(contract.get(field), False, "SOURCE_BINDING_MISMATCH", f"capture_contract.{field}")
    if (
        contract.get("capture_id") != "final_structural_pre_origin"
        or contract.get("capture_not_before_utc") != "2026-10-29T13:30:00Z"
        or contract.get("capture_deadline_utc") != "2026-10-30T13:45:00Z"
        or contract.get("origin_timestamp_utc") != "2026-10-30T14:00:00Z"
        or contract.get("request_method") != "GET"
        or contract.get("request_payload_sha256") != EMPTY_SHA256
        or _exact_int(contract.get("source_object_count"), "SOURCE_BINDING_MISMATCH", "source_object_count") != 6
    ):
        fail("SOURCE_BINDING_MISMATCH", "capture geometry drifted")
    objects = profile.get("objects")
    profiles = profile.get("profiles")
    dispatches = profile.get("dispatches")
    if type(objects) is not list or len(objects) != 6:
        fail("SOURCE_BINDING_MISMATCH", "object topology drifted")
    if type(profiles) is not list or len(profiles) != 6:
        fail("SOURCE_BINDING_MISMATCH", "profile topology drifted")
    if type(dispatches) is not list or len(dispatches) != 2:
        fail("SOURCE_BINDING_MISMATCH", "dispatch topology drifted")
    object_ids = [item.get("object_id") for item in objects if type(item) is dict]
    if object_ids != sorted(object_ids) or len(set(object_ids)) != 6:
        fail("SOURCE_BINDING_MISMATCH", "object IDs are not exact sorted unique values")
    if [item.get("request_ordinal") for item in objects] != list(range(1, 7)):
        fail("SOURCE_BINDING_MISMATCH", "request ordinals drifted")
    if any(item.get("present_body_expected_in_live_capture") is not False for item in objects):
        fail("SOURCE_BINDING_MISMATCH", "present hashes became a live body allowlist")
    if [item.get("object_id") for item in profiles] != object_ids:
        fail("SOURCE_BINDING_MISMATCH", "profile-to-object bijection drifted")
    if any(item.get("supersession_state") != "UNAPPROVED_REQUIRED" for item in profiles):
        fail("SOURCE_BINDING_MISMATCH", "supersession ceiling drifted")
    claim = profile.get("claim_ceiling")
    if type(claim) is not dict or claim != {
        "current_bytes_status": "NONPROSPECTIVE_PRESENT_DAY_DIAGNOSTIC_BYTES",
        "maximum_status": "CANNOT_RUN",
        "present_body_hashes_are_live_allowlist": False,
        "present_body_hashes_are_test_oracles_only": True,
        "self_acceptance_allowed": False,
        "successor_required_for_qualified_leaf": True,
    }:
        fail("SOURCE_BINDING_MISMATCH", "claim ceiling drifted")
    return profile


def _verify_source_pins(profile: Mapping[str, Any]) -> None:
    pins = profile.get("source_pins")
    if type(pins) is not list or len(pins) != len(EXPECTED_SOURCE_PINS):
        fail("SOURCE_BINDING_MISMATCH", "source-pin topology drifted")
    declared = []
    for index, pin in enumerate(pins):
        item = _exact_keys(
            pin,
            ["binding_id", "path", "sha256"],
            "SOURCE_BINDING_MISMATCH",
            f"source_pins[{index}]",
        )
        declared.append((item["binding_id"], item["path"], item["sha256"]))
    if tuple(declared) != EXPECTED_SOURCE_PINS:
        fail("SOURCE_BINDING_MISMATCH", "profile-declared source pins differ from module authority")
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    for binding_id, relative, expected in EXPECTED_SOURCE_PINS:
        if type(binding_id) is not str or binding_id in seen_ids:
            fail("SOURCE_BINDING_MISMATCH", "duplicate or invalid source binding ID")
        if type(relative) is not str or relative in seen_paths or relative.startswith(("/", "../")):
            fail("SOURCE_BINDING_MISMATCH", "duplicate or unsafe source path")
        if type(expected) is not str or HASH_PATTERN.fullmatch(expected) is None:
            fail("SOURCE_BINDING_MISMATCH", "malformed source SHA-256")
        path = Path(os.path.abspath(REPOSITORY_ROOT / relative))
        try:
            path.relative_to(REPOSITORY_ROOT)
        except ValueError:
            fail("SOURCE_BINDING_MISMATCH", "source path escapes repository root")
        raw = _safe_read_file(path, 32 * 1024 * 1024, f"source pin {binding_id}")
        if sha256_bytes(raw) != expected:
            fail("SOURCE_BINDING_MISMATCH", f"source pin drifted: {binding_id}")
        seen_ids.add(binding_id)
        seen_paths.add(relative)


def validate_profile() -> dict[str, Any]:
    """Validate the exact adjacent profile and every frozen source pin."""

    profile = _load_and_check_profile()
    _verify_source_pins(profile)
    return json.loads(json.dumps(profile, ensure_ascii=False))


def _framed_digest(row: Mapping[str, str], fields: Sequence[str], domain: bytes) -> bytes:
    digest = hashlib.sha256(domain)
    for field in fields:
        name = field.encode("utf-8")
        value = row[field].encode("utf-8")
        digest.update(struct.pack(">I", len(name)))
        digest.update(name)
        digest.update(struct.pack(">Q", len(value)))
        digest.update(value)
    return digest.digest()


def _subject_sha256(kind: str, value: Any) -> str:
    payload = canonical_json_bytes({"kind": kind, "value": value})
    return sha256_bytes(payload)


def _validate_injected_objects(
    objects: Any,
    profile: Mapping[str, Any],
    *,
    require_full: bool,
) -> dict[str, dict[str, Any]]:
    if type(objects) is not dict or any(type(key) is not str for key in objects):
        fail("CAPTURE_SET_MEMBERSHIP_OR_ORDER_FAILED", "objects must be one concrete string-keyed dict")
    expected = [item["object_id"] for item in profile["objects"]]
    actual = list(objects)
    if require_full:
        if actual != expected:
            fail("CAPTURE_SET_MEMBERSHIP_OR_ORDER_FAILED", "exact ordered six-object membership is required")
    else:
        if actual != [item for item in expected if item in objects]:
            fail("CAPTURE_SET_MEMBERSHIP_OR_ORDER_FAILED", "partial objects must retain source order")
        if any(item not in expected for item in actual):
            fail("CAPTURE_SET_MEMBERSHIP_OR_ORDER_FAILED", "partial set contains an unknown object")
    normalized: dict[str, dict[str, Any]] = {}
    plans = {item["object_id"]: item for item in profile["objects"]}
    for object_id in actual:
        item = _exact_keys(
            objects[object_id],
            ["body", "raw_headers", "transport"],
            "CAPTURE_SET_MEMBERSHIP_OR_ORDER_FAILED",
            f"objects.{object_id}",
        )
        if type(item["body"]) is not bytes or type(item["raw_headers"]) is not bytes:
            fail("CAPTURE_SET_MEMBERSHIP_OR_ORDER_FAILED", "body/header values must be concrete bytes")
        transport = _exact_keys(
            item["transport"],
            [
                "cookies_sent",
                "credentials_sent",
                "effective_url",
                "method",
                "netrc_used",
                "proxy_used",
                "range_requested",
                "redirect_count",
                "request_body",
                "requested_url",
                "response_completed_at_utc",
                "response_started_at_utc",
                "retry_count",
                "transaction_state",
            ],
            "HTTP_RESPONSE_CONTRACT_FAILED",
            f"objects.{object_id}.transport",
        )
        for field in (
            "cookies_sent",
            "credentials_sent",
            "netrc_used",
            "proxy_used",
            "range_requested",
        ):
            _exact_bool(transport[field], False, "HTTP_RESPONSE_CONTRACT_FAILED", field)
        for field in ("redirect_count", "retry_count"):
            if _exact_int(transport[field], "HTTP_RESPONSE_CONTRACT_FAILED", field) != 0:
                fail("HTTP_RESPONSE_CONTRACT_FAILED", f"{field} must be zero")
        if type(transport["method"]) is not str or transport["method"] != "GET":
            fail("HTTP_RESPONSE_CONTRACT_FAILED", "request method must be GET")
        if type(transport["request_body"]) is not bytes or transport["request_body"] != b"":
            fail("HTTP_RESPONSE_CONTRACT_FAILED", "request payload must be empty concrete bytes")
        planned_url = plans[object_id]["planned_url"]
        if (
            type(transport["requested_url"]) is not str
            or type(transport["effective_url"]) is not str
            or transport["requested_url"] != planned_url
            or transport["effective_url"] != planned_url
        ):
            fail("REDIRECT_OR_EFFECTIVE_URI_MISMATCH", "requested/effective URL differs from exact plan")
        if transport["transaction_state"] != "COMPLETE":
            fail("REQUEST_STATE_UNCERTAIN_NO_RETRY", "injected complete object has uncertain transaction state")
        started = _parse_utc_timestamp(transport["response_started_at_utc"], "response_started_at_utc")
        completed = _parse_utc_timestamp(transport["response_completed_at_utc"], "response_completed_at_utc")
        if completed < started:
            fail("BODY_SIZE_LENGTH_OR_TIME_FAILED", "response completion precedes response start")
        normalized[object_id] = {
            "body": item["body"],
            "raw_headers": item["raw_headers"],
            "transport": dict(transport),
        }
    return normalized


def _parse_utc_timestamp(value: Any, location: str) -> datetime:
    if type(value) is not str or UTC_TIMESTAMP_PATTERN.fullmatch(value) is None:
        fail("BODY_SIZE_LENGTH_OR_TIME_FAILED", f"{location} is not exact whole-second UTC")
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as error:
        fail("BODY_SIZE_LENGTH_OR_TIME_FAILED", f"invalid {location}: {error}")
    return parsed


def _parse_raw_headers(
    raw: bytes,
    expected_media: str,
    body_size: int,
    limits: Mapping[str, Any],
) -> dict[str, Any]:
    maximum_bytes = limits["max_header_bytes"]
    if not raw or len(raw) > maximum_bytes or b"\x00" in raw:
        fail("HTTP_RESPONSE_CONTRACT_FAILED", "raw headers are empty, oversized, or contain NUL")
    if not raw.endswith(b"\r\n\r\n") or b"\n\n" in raw:
        fail("HTTP_RESPONSE_CONTRACT_FAILED", "raw headers must use one CRLF-terminated block")
    lines = raw[:-4].split(b"\r\n")
    if not lines or HTTP_STATUS_PATTERN.fullmatch(lines[0]) is None:
        fail("HTTP_RESPONSE_CONTRACT_FAILED", "HTTP status line is not exact 200")
    if len(lines) - 1 > limits["max_header_count"]:
        fail("HTTP_RESPONSE_CONTRACT_FAILED", "header-count ceiling exceeded")
    headers: dict[str, str] = {}
    order: list[str] = []
    for line in lines[1:]:
        if b":" not in line:
            fail("HTTP_RESPONSE_CONTRACT_FAILED", "malformed raw header line")
        name_raw, value_raw = line.split(b":", 1)
        if (
            len(name_raw) > limits["max_header_name_bytes"]
            or len(value_raw) > limits["max_header_value_bytes"]
            or HEADER_NAME_PATTERN.fullmatch(name_raw) is None
        ):
            fail("HTTP_RESPONSE_CONTRACT_FAILED", "invalid header name")
        try:
            name = name_raw.decode("ascii").lower()
            value = value_raw.decode("latin-1").strip(" \t")
        except UnicodeDecodeError:
            fail("HTTP_RESPONSE_CONTRACT_FAILED", "invalid header bytes")
        if name in headers:
            fail("HTTP_RESPONSE_CONTRACT_FAILED", f"duplicate header {name}")
        if any(
            (ord(character) < 0x20 and character != "\t") or ord(character) == 0x7F
            for character in value
        ):
            fail("HTTP_RESPONSE_CONTRACT_FAILED", "header value contains controls")
        headers[name] = value
        order.append(name)
    if any(name in headers for name in ("location", "content-range", "transfer-encoding")):
        fail("HTTP_RESPONSE_CONTRACT_FAILED", "redirect/range/transfer ambiguity header is forbidden")
    content_type = headers.get("content-type")
    if content_type is None:
        fail("MEDIA_OR_CONTENT_ENCODING_MISMATCH", "Content-Type is absent")
    base_media = content_type.split(";", 1)[0].strip().lower()
    if base_media != expected_media:
        fail("MEDIA_OR_CONTENT_ENCODING_MISMATCH", f"expected {expected_media}, got {base_media}")
    encoding = headers.get("content-encoding", "")
    if encoding.lower() not in ("", "identity"):
        fail("MEDIA_OR_CONTENT_ENCODING_MISMATCH", "HTTP Content-Encoding must be absent or identity")
    if "content-length" not in headers:
        fail("BODY_SIZE_LENGTH_OR_TIME_FAILED", "Content-Length is required")
    length = headers["content-length"]
    if NONNEGATIVE_INTEGER_PATTERN.fullmatch(length) is None or int(length) != body_size:
        fail("BODY_SIZE_LENGTH_OR_TIME_FAILED", "Content-Length differs from body bytes")
    return {
        "base_media_type": base_media,
        "content_encoding": encoding if encoding else "ABSENT",
        "content_length": body_size,
        "header_names_in_order": order,
        "raw_header_bytes": len(raw),
        "raw_header_sha256": sha256_bytes(raw),
        "raw_headers_authenticated": False,
    }


def _strict_ascii_lines(raw: bytes, location: str) -> list[str]:
    if (
        raw.startswith((b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff"))
        or b"\x00" in raw
        or b"\r" in raw
        or not raw.endswith(b"\n")
    ):
        fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", f"{location} BOM/NUL/newline contract failed")
    try:
        text = raw.decode("ascii")
    except UnicodeDecodeError:
        fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", f"{location} is not strict US-ASCII")
    lines = text[:-1].split("\n")
    if any(line == "" for line in lines):
        fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", f"{location} contains a blank physical line")
    return lines


def _zip_eocd_exact(raw: bytes) -> None:
    signature = b"PK\x05\x06"
    position = raw.rfind(signature, max(0, len(raw) - 65_557))
    if position < 0 or position + 22 > len(raw):
        fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", "terminal EOCD is absent")
    comment_length = struct.unpack_from("<H", raw, position + 20)[0]
    if comment_length != 0 or position + 22 != len(raw):
        fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", "archive comment or trailing bytes are forbidden")
    if b"PK\x06\x06" in raw or b"PK\x06\x07" in raw:
        fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", "ZIP64 is forbidden")


def _parse_aies(
    body: bytes,
    object_plan: Mapping[str, Any],
    profile_plan: Mapping[str, Any],
    limits: Mapping[str, Any],
) -> tuple[dict[str, Any], tuple[dict[str, str], ...]]:
    if not body.startswith(b"PK\x03\x04") or len(body) > limits["max_aies_zip_bytes"]:
        fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", "ZIP signature/size contract failed")
    _zip_eocd_exact(body)
    product = object_plan["product_code"]
    expected_names = [
        product + ".dat",
        product + "_FIELDS.txt",
        product + "_README.txt",
    ]
    try:
        archive = zipfile.ZipFile(io.BytesIO(body), "r")
    except (OSError, zipfile.BadZipFile) as error:
        fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", f"invalid ZIP: {error}")
    with archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if names != expected_names or len(set(name.casefold() for name in names)) != 3:
            fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", "exact ordered three-member set is required")
        total_uncompressed = 0
        member_records: list[dict[str, Any]] = []
        payloads: dict[str, bytes] = {}
        for info in infos:
            if (
                info.flag_bits & 0x1
                or info.compress_type != zipfile.ZIP_DEFLATED
                or info.file_size < 1
                or info.file_size > limits["max_aies_member_bytes"]
                or info.compress_size < 1
                or info.filename.startswith(("/", "\\"))
                or ".." in Path(info.filename).parts
                or "/" in info.filename
                or "\\" in info.filename
            ):
                fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", f"member metadata invalid: {info.filename}")
            total_uncompressed += info.file_size
            if total_uncompressed > limits["max_aies_total_uncompressed_bytes"]:
                fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", "aggregate expansion ceiling exceeded")
            if info.file_size > info.compress_size * limits["max_compression_ratio"]:
                fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", "compression-ratio ceiling exceeded")
            try:
                payload = archive.read(info)
            except (OSError, RuntimeError, zipfile.BadZipFile) as error:
                fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", f"member integrity failed: {error}")
            payloads[info.filename] = payload
            member_records.append(
                {
                    "compressed_bytes": info.compress_size,
                    "compression_method": info.compress_type,
                    "crc32": f"{info.CRC:08x}",
                    "name": info.filename,
                    "sha256": sha256_bytes(payload),
                    "uncompressed_bytes": info.file_size,
                }
            )
        if archive.testzip() is not None:
            fail("AIES_CONTAINER_OR_MEMBER_CONTRACT_FAILED", "member CRC replay failed")
    dat_lines = _strict_ascii_lines(payloads[expected_names[0]], expected_names[0])
    field_lines = _strict_ascii_lines(payloads[expected_names[1]], expected_names[1])
    _strict_ascii_lines(payloads[expected_names[2]], expected_names[2])
    if not dat_lines[0].startswith("#") or dat_lines[0].startswith("##"):
        fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", "DAT header marker drifted")
    header = dat_lines[0][1:].split("|")
    if header != profile_plan["physical_header"] or len(header) != len(set(header)):
        fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", "DAT header/order drifted")
    if field_lines[0].split("|") != [
        "Field_Name",
        "Label",
        "Field_Type",
        "Field_Length",
        "Number_of_Decimals",
    ]:
        fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", "FIELDS header drifted")
    metadata: dict[str, tuple[str, int, int]] = {}
    metadata_order: list[str] = []
    for line in field_lines[1:]:
        parts = line.split("|")
        if len(parts) != 5 or not parts[0] or not parts[1]:
            fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", "malformed FIELDS row")
        name, _label, kind, width, decimals = parts
        if (
            name in metadata
            or kind not in ("CHARACTER", "NUMBER")
            or NONNEGATIVE_INTEGER_PATTERN.fullmatch(width) is None
            or NONNEGATIVE_INTEGER_PATTERN.fullmatch(decimals) is None
            or not 1 <= int(width) <= limits["max_field_bytes"]
            or int(decimals) > 9
        ):
            fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", "invalid FIELDS metadata")
        metadata[name] = (kind, int(width), int(decimals))
        metadata_order.append(name)
    if metadata_order != header:
        fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", "FIELDS order differs from DAT header")
    row_lines = dat_lines[1:]
    if not 1 <= len(row_lines) <= limits["max_aies_rows"]:
        fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", "AIES row-count ceiling failed")
    rows: list[dict[str, str]] = []
    key_seen: set[tuple[str, ...]] = set()
    row_digests: list[bytes] = []
    key_digests: list[bytes] = []
    row_order = hashlib.sha256(b"AIES_PROSPECTIVE_PHYSICAL_ROW_ORDER_V2")
    flag_counts: dict[str, dict[str, int]] = {
        field: {} for field in header if field.endswith("_F")
    }
    blank_counts: dict[str, int] = {field: 0 for field in header}
    signed_negative_counts: dict[str, int] = {}
    zero_plus_flag_count = 0
    semantics = _load_and_check_profile()["semantics"]["aies"]
    measure_flags = set(semantics["allowed_measure_flag_lexemes"])
    naics_flags = set(semantics["allowed_naics_flag_lexemes"])
    geo_flags = set(semantics["geographic_flag_lexemes"])
    key_fields = profile_plan["key_fields"]
    for ordinal, line in enumerate(row_lines, 1):
        if '"' in line:
            fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", f"quoted DAT field at row {ordinal}")
        values = line.split("|")
        if len(values) != len(header):
            fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", f"row width drifted at {ordinal}")
        row = dict(zip(header, values, strict=True))
        for field, value in row.items():
            if value != value.strip() or any(ord(character) < 0x20 for character in value):
                fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", f"lexical whitespace/control in {field}")
            if len(value.encode("ascii")) > metadata[field][1]:
                fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", f"field width exceeded in {field}")
            if metadata[field][0] == "NUMBER":
                if SIGNED_DECIMAL_PATTERN.fullmatch(value) is None:
                    fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", f"invalid signed decimal in {field}")
                if value.startswith("-"):
                    signed_negative_counts[field] = signed_negative_counts.get(field, 0) + 1
            if value == "":
                blank_counts[field] += 1
            if field.endswith("_F"):
                allowed = geo_flags if field == "GEO_ID_F" else naics_flags if field == "NAICS_F" else measure_flags
                if value not in allowed:
                    fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", f"unknown case-sensitive flag {field}={value!r}")
                counts = flag_counts[field]
                counts[value] = counts.get(value, 0) + 1
        for field in header:
            if field.endswith("_F") and field not in ("GEO_ID_F", "NAICS_F"):
                base = field[:-2]
                if base in row and row[base] in ("0", "0.0", ".0", "-.0") and row[field] != "":
                    zero_plus_flag_count += 1
        key = tuple(row[field] for field in key_fields)
        if key in key_seen:
            fail("AIES_PHYSICAL_SCHEMA_OR_ROW_FAILED", f"duplicate key at row {ordinal}")
        key_seen.add(key)
        row_digest = _framed_digest(row, header, b"AIES_PROSPECTIVE_PHYSICAL_ROW_V2")
        key_digest = _framed_digest(row, key_fields, b"AIES_PROSPECTIVE_PHYSICAL_KEY_V2")
        row_order.update(row_digest)
        row_digests.append(row_digest)
        key_digests.append(key_digest)
        rows.append(row)
    diagnostic = {
        "all_official_rows_retained": True,
        "blank_counts": {key: value for key, value in sorted(blank_counts.items()) if value},
        "character_encoding": "US-ASCII",
        "data_member": expected_names[0],
        "delimiter": "|",
        "dictionary_member": expected_names[1],
        "field_count": len(header),
        "flag_case_and_measure_pairing_preserved": True,
        "flag_lexeme_counts": {
            field: dict(sorted(counts.items())) for field, counts in sorted(flag_counts.items())
        },
        "key_fields": list(key_fields),
        "key_membership_sha256": sha256_bytes(b"".join(sorted(key_digests))),
        "member_records": member_records,
        "numeric_absolute_value_applied": False,
        "physical_header": header,
        "readme_member": expected_names[2],
        "row_count": len(rows),
        "row_membership_sha256": sha256_bytes(b"".join(sorted(row_digests))),
        "row_order_sha256": row_order.hexdigest(),
        "signed_negative_counts": dict(sorted(signed_negative_counts.items())),
        "value_or_dimension_normalization_performed": False,
        "zero_plus_flag_count": zero_plus_flag_count,
    }
    diagnostic["physical_table_subject_sha256"] = _subject_sha256("aies-physical-table-v2", diagnostic)
    return diagnostic, tuple(rows)
