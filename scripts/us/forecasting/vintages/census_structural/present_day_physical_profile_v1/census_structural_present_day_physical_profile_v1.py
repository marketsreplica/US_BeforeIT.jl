#!/usr/bin/env python3
"""Parse six frozen present-day Census structural files, diagnostically only.

This module deliberately has no network or future-capture mode.  Local hashes
and response-header bytes establish local fixity, not Census origin, transport
authentication, custody, availability, qualification, or model admissibility.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import stat
import struct
import sys
import tomllib
import zipfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence

sys.dont_write_bytecode = True

SCHEMA_VERSION = "beforeit-us-census-structural-present-day-physical-result.v1"
PROFILE_SCHEMA_VERSION = (
    "beforeit-us-census-structural-present-day-physical-profile.v1"
)
STATUS = "CANNOT_RUN"
ROLE = "PRESENT_DAY_PHYSICAL_LAYOUT_DIAGNOSTIC_NONADMITTING"
CANONICALIZATION = "utf8-sorted-keys-compact-json-lf.v1"
EXPECTED_PROFILE_PHYSICAL_SHA256 = (
    "556fb4319ddc05779bb785588b32df60704ff4a276f8a133b58cef59710b9673"
)
EXPECTED_LOGICAL_PROFILE_PHYSICAL_SHA256 = (
    "512b35c1d80c9d6c8b387cdd68affd4a1ae92b1dc040c04aacae8545b47ef157"
)
EXPECTED_LOGICAL_PROFILE_SEMANTIC_SHA256 = (
    "c661bc84b0b9f9ee3c6ff28982721a9a9dacd14d6e73cc6859db54737429b491"
)
MODULE_PATH = Path(os.path.abspath(__file__))
PROFILE_PATH = MODULE_PATH.with_name(
    "census_structural_present_day_physical_profile_v1.json"
)
LOGICAL_DIR = MODULE_PATH.parent.parent / "profile_v1"

SOURCE_IDS = (
    "aies00inv_2023_economy_wide",
    "aies31inv_2023_manufacturing_valuation",
    "aies42inv_2023_wholesale_valuation",
    "aies44inv_2023_retail_valuation",
    "aies51inv_2023_information_stages",
    "susb_employer_enterprises",
)
SOURCE_DECLARATIONS = (
    (
        SOURCE_IDS[0],
        "AIES00INV.zip",
        "https://www2.census.gov/programs-surveys/aies/data/2023/AIES00INV.zip",
        "aies_zip",
    ),
    (
        SOURCE_IDS[1],
        "AIES31INV.zip",
        "https://www2.census.gov/programs-surveys/aies/data/2023/AIES31INV.zip",
        "aies_zip",
    ),
    (
        SOURCE_IDS[2],
        "AIES42INV.zip",
        "https://www2.census.gov/programs-surveys/aies/data/2023/AIES42INV.zip",
        "aies_zip",
    ),
    (
        SOURCE_IDS[3],
        "AIES44INV.zip",
        "https://www2.census.gov/programs-surveys/aies/data/2023/AIES44INV.zip",
        "aies_zip",
    ),
    (
        SOURCE_IDS[4],
        "AIES51INV.zip",
        "https://www2.census.gov/programs-surveys/aies/data/2023/AIES51INV.zip",
        "aies_zip",
    ),
    (
        SOURCE_IDS[5],
        "us_state_6digitnaics_2022.txt",
        "https://www2.census.gov/programs-surveys/susb/tables/2022/"
        "us_state_6digitnaics_2022.txt",
        "susb_text",
    ),
)
LOGICAL_ARTIFACTS = (
    (
        "USCensusStructuralProfileV1.jl",
        "e0a683586a44d0cba8129d7494c49e00e1606453c46e94b37f60d4804f450f68",
    ),
    (
        "census_structural_profile_v1.toml",
        EXPECTED_LOGICAL_PROFILE_PHYSICAL_SHA256,
    ),
    (
        "test_census_structural_profile_v1.jl",
        "ef2089d3fb47400947111f8b8a743999c42c0092b547d70e8be7c9708447cd55",
    ),
    (
        "README.md",
        "4a734c3fe7239dc686b9fe0de53075ec5a4d0c3b96d31298c2be3d8d45a980e5",
    ),
)
HARD_FALSE_GATES = (
    "origin_admissible",
    "provider_provenance_verified",
    "transport_authenticated",
    "response_header_authenticity_verified",
    "custody_verified",
    "availability_verified",
    "policy_qualified",
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
MAX_PROFILE_BYTES = 2 * 1024 * 1024
MAX_HEADER_BYTES = 32 * 1024
MAX_AIES_ZIP_BYTES = 2 * 1024 * 1024
MAX_SUSB_BYTES = 64 * 1024 * 1024
MAX_AIES_MEMBER_BYTES = 4 * 1024 * 1024
MAX_AIES_TOTAL_UNCOMPRESSED = 12 * 1024 * 1024
MAX_COMPRESSION_RATIO = 100
MAX_AIES_ROWS = 2_000
MAX_SUSB_ROWS = 600_000
MAX_FIELD_BYTES = 512


class ProfileError(RuntimeError):
    """A closed-world physical or policy check failed."""


@dataclass(frozen=True)
class AIESParsed:
    public: dict[str, Any]
    rows: tuple[dict[str, str], ...]
    logical: Mapping[str, Any]


class _HashingTextSink:
    """Minimal csv.writer sink that hashes canonical Windows-1252 output."""

    def __init__(self) -> None:
        self.digest = hashlib.sha256()
        self.byte_count = 0

    def write(self, value: str) -> int:
        encoded = value.encode("cp1252")
        self.digest.update(encoded)
        self.byte_count += len(encoded)
        return len(value)


def fail(message: str) -> None:
    raise ProfileError(message)


def _check_static_policy() -> None:
    if (
        SCHEMA_VERSION
        != "beforeit-us-census-structural-present-day-physical-result.v1"
        or PROFILE_SCHEMA_VERSION
        != "beforeit-us-census-structural-present-day-physical-profile.v1"
        or STATUS != "CANNOT_RUN"
        or ROLE != "PRESENT_DAY_PHYSICAL_LAYOUT_DIAGNOSTIC_NONADMITTING"
        or CANONICALIZATION != "utf8-sorted-keys-compact-json-lf.v1"
        or EXPECTED_PROFILE_PHYSICAL_SHA256
        != "556fb4319ddc05779bb785588b32df60704ff4a276f8a133b58cef59710b9673"
        or EXPECTED_LOGICAL_PROFILE_PHYSICAL_SHA256
        != "512b35c1d80c9d6c8b387cdd68affd4a1ae92b1dc040c04aacae8545b47ef157"
        or EXPECTED_LOGICAL_PROFILE_SEMANTIC_SHA256
        != "c661bc84b0b9f9ee3c6ff28982721a9a9dacd14d6e73cc6859db54737429b491"
        or SOURCE_IDS
        != (
            "aies00inv_2023_economy_wide",
            "aies31inv_2023_manufacturing_valuation",
            "aies42inv_2023_wholesale_valuation",
            "aies44inv_2023_retail_valuation",
            "aies51inv_2023_information_stages",
            "susb_employer_enterprises",
        )
        or MODULE_PATH != Path(os.path.abspath(__file__))
        or PROFILE_PATH
        != Path(os.path.abspath(__file__)).with_name(
            "census_structural_present_day_physical_profile_v1.json"
        )
        or LOGICAL_DIR
        != Path(os.path.abspath(__file__)).parent.parent / "profile_v1"
        or HARD_FALSE_GATES
        != (
            "origin_admissible",
            "provider_provenance_verified",
            "transport_authenticated",
            "response_header_authenticity_verified",
            "custody_verified",
            "availability_verified",
            "policy_qualified",
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
        or SOURCE_DECLARATIONS
        != (
            (
                "aies00inv_2023_economy_wide",
                "AIES00INV.zip",
                "https://www2.census.gov/programs-surveys/aies/data/2023/AIES00INV.zip",
                "aies_zip",
            ),
            (
                "aies31inv_2023_manufacturing_valuation",
                "AIES31INV.zip",
                "https://www2.census.gov/programs-surveys/aies/data/2023/AIES31INV.zip",
                "aies_zip",
            ),
            (
                "aies42inv_2023_wholesale_valuation",
                "AIES42INV.zip",
                "https://www2.census.gov/programs-surveys/aies/data/2023/AIES42INV.zip",
                "aies_zip",
            ),
            (
                "aies44inv_2023_retail_valuation",
                "AIES44INV.zip",
                "https://www2.census.gov/programs-surveys/aies/data/2023/AIES44INV.zip",
                "aies_zip",
            ),
            (
                "aies51inv_2023_information_stages",
                "AIES51INV.zip",
                "https://www2.census.gov/programs-surveys/aies/data/2023/AIES51INV.zip",
                "aies_zip",
            ),
            (
                "susb_employer_enterprises",
                "us_state_6digitnaics_2022.txt",
                "https://www2.census.gov/programs-surveys/susb/tables/2022/"
                "us_state_6digitnaics_2022.txt",
                "susb_text",
            ),
        )
        or LOGICAL_ARTIFACTS
        != (
            (
                "USCensusStructuralProfileV1.jl",
                "e0a683586a44d0cba8129d7494c49e00e1606453c46e94b37f60d4804f450f68",
            ),
            (
                "census_structural_profile_v1.toml",
                "512b35c1d80c9d6c8b387cdd68affd4a1ae92b1dc040c04aacae8545b47ef157",
            ),
            (
                "test_census_structural_profile_v1.jl",
                "ef2089d3fb47400947111f8b8a743999c42c0092b547d70e8be7c9708447cd55",
            ),
            (
                "README.md",
                "4a734c3fe7239dc686b9fe0de53075ec5a4d0c3b96d31298c2be3d8d45a980e5",
            ),
        )
        or (
            MAX_PROFILE_BYTES,
            MAX_HEADER_BYTES,
            MAX_AIES_ZIP_BYTES,
            MAX_SUSB_BYTES,
            MAX_AIES_MEMBER_BYTES,
            MAX_AIES_TOTAL_UNCOMPRESSED,
            MAX_COMPRESSION_RATIO,
            MAX_AIES_ROWS,
            MAX_SUSB_ROWS,
            MAX_FIELD_BYTES,
        )
        != (
            2 * 1024 * 1024,
            32 * 1024,
            2 * 1024 * 1024,
            64 * 1024 * 1024,
            4 * 1024 * 1024,
            12 * 1024 * 1024,
            100,
            2_000,
            600_000,
            512,
        )
    ):
        fail("module policy state was modified in process")


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
        raise ProfileError("value is not canonical JSON") from error
    return (text + "\n").encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hard_false_gates() -> dict[str, bool]:
    return {name: False for name in HARD_FALSE_GATES}


def _duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail("duplicate JSON key: " + key)
        result[key] = value
    return result


def _nonfinite(value: str) -> None:
    fail("non-finite JSON token: " + value)


def parse_json_bytes(data: bytes, location: str) -> dict[str, Any]:
    if data.startswith(b"\xef\xbb\xbf"):
        fail(location + " has a forbidden BOM")
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_duplicate_keys,
            parse_constant=_nonfinite,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ProfileError(location + " is not strict UTF-8 JSON") from error
    if not isinstance(value, dict):
        fail(location + " must be one JSON object")
    return value


def _is_sha256(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _exact_int(value: Any, location: str) -> int:
    if type(value) is not int or value < 0:
        fail(location + " must be an exact nonnegative integer")
    return value


def _exact_text(value: Any, location: str) -> str:
    if not isinstance(value, str) or not value:
        fail(location + " must be nonempty text")
    return value


def _expect_keys(value: Any, keys: tuple[str, ...], location: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != set(keys):
        fail(location + " keys drifted")
    return value


def _profile_semantic_hash(profile: Mapping[str, Any]) -> str:
    copy = parse_json_bytes(canonical_json_bytes(profile), "profile copy")
    artifact = copy.get("artifact")
    if not isinstance(artifact, dict) or "content_sha256" not in artifact:
        fail("profile semantic hash field is absent")
    del artifact["content_sha256"]
    return sha256_bytes(canonical_json_bytes(copy))


def _read_regular_absolute(path: Path, location: str, cap: int) -> bytes:
    if not isinstance(path, Path) or not path.is_absolute():
        fail(location + " path must be an absolute Path")
    absolute = Path(os.path.abspath(os.fspath(path)))
    if absolute != path or absolute.resolve(strict=True) != absolute:
        fail(location + " path is not canonical or contains an alias")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(absolute, flags)
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_nlink != 1
            or before.st_size > cap
        ):
            fail(location + " is not a bounded single-link regular file")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(1024 * 1024, cap + 1 - total))
            if not chunk:
                break
            total += len(chunk)
            if total > cap:
                fail(location + " exceeds its byte ceiling")
            chunks.append(chunk)
        after = os.fstat(descriptor)
        current = os.stat(absolute, follow_symlinks=False)
        fields = (
            "st_dev",
            "st_ino",
            "st_mode",
            "st_nlink",
            "st_size",
            "st_mtime_ns",
            "st_ctime_ns",
        )
        if any(
            getattr(before, field) != getattr(after, field)
            or getattr(before, field) != getattr(current, field)
            for field in fields
        ):
            fail(location + " changed during its pinned read")
        result = b"".join(chunks)
        if len(result) != before.st_size:
            fail(location + " size changed during its pinned read")
        return result
    finally:
        os.close(descriptor)


def _logical_contract() -> tuple[dict[str, Any], dict[str, str]]:
    hashes: dict[str, str] = {}
    toml_bytes = b""
    for filename, expected in LOGICAL_ARTIFACTS:
        body = _read_regular_absolute(
            LOGICAL_DIR / filename, "logical contract " + filename, MAX_PROFILE_BYTES
        )
        actual = sha256_bytes(body)
        if actual != expected:
            fail("accepted logical-contract dependency drifted: " + filename)
        hashes[filename] = actual
        if filename.endswith(".toml"):
            toml_bytes = body
    try:
        contract = tomllib.loads(toml_bytes.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as error:
        raise ProfileError("accepted logical profile is not strict TOML") from error
    artifact = contract.get("artifact")
    if (
        not isinstance(artifact, dict)
        or artifact.get("content_sha256")
        != EXPECTED_LOGICAL_PROFILE_SEMANTIC_SHA256
        or artifact.get("status") != "CANNOT_RUN"
        or artifact.get("role") != "LOGICAL_SCHEMA_MECHANICS_ONLY"
    ):
        fail("accepted logical-contract identity or ceiling drifted")
    profiles = contract.get("profiles")
    if (
        not isinstance(profiles, list)
        or tuple(item.get("profile_id") for item in profiles if isinstance(item, dict))
        != SOURCE_IDS
    ):
        fail("accepted logical-contract six-profile topology drifted")
    for declaration, record in zip(SOURCE_DECLARATIONS, profiles, strict=True):
        if record.get("source_url") != declaration[2]:
            fail("accepted logical source URL drifted for " + declaration[0])
    return contract, hashes


def _load_profile() -> tuple[dict[str, Any], dict[str, Any], dict[str, str]]:
    _check_static_policy()
    raw = _read_regular_absolute(PROFILE_PATH, "physical profile", MAX_PROFILE_BYTES)
    if sha256_bytes(raw) != EXPECTED_PROFILE_PHYSICAL_SHA256:
        fail("physical profile SHA-256 drifted")
    profile = parse_json_bytes(raw, "physical profile")
    artifact = _expect_keys(
        profile.get("artifact"),
        (
            "schema_version",
            "status",
            "role",
            "canonicalization",
            "content_sha256",
            "logical_profile_physical_sha256",
            "logical_profile_semantic_sha256",
        ),
        "profile.artifact",
    )
    if (
        artifact["schema_version"] != PROFILE_SCHEMA_VERSION
        or artifact["status"] != STATUS
        or artifact["role"] != ROLE
        or artifact["canonicalization"] != CANONICALIZATION
        or artifact["logical_profile_physical_sha256"]
        != EXPECTED_LOGICAL_PROFILE_PHYSICAL_SHA256
        or artifact["logical_profile_semantic_sha256"]
        != EXPECTED_LOGICAL_PROFILE_SEMANTIC_SHA256
        or not _is_sha256(artifact["content_sha256"])
    ):
        fail("physical profile artifact drifted")
    if _profile_semantic_hash(profile) != artifact["content_sha256"]:
        fail("physical profile semantic self-hash is invalid")
    _expect_keys(
        profile,
        ("artifact", "boundary", "sources", "cross_source", "gates"),
        "profile",
    )
    boundary = profile["boundary"]
    if not isinstance(boundary, dict):
        fail("profile.boundary is malformed")
    required_true = (
        "present_day_only",
        "external_bodies_required",
        "source_verification_mandatory",
        "successor_required_for_any_qualification",
        "logical_incompatibilities_must_remain_lossless",
        "independent_audit_required",
    )
    required_false = (
        "body_to_url_provenance_claimed",
        "provider_authenticated",
        "transport_authenticated",
        "custody_claimed",
        "availability_claimed",
        "logical_contract_compatible",
        "future_compatibility_claimed",
        "self_accepted",
    )
    if any(boundary.get(key) is not True for key in required_true) or any(
        boundary.get(key) is not False for key in required_false
    ):
        fail("profile boundary ceiling drifted")
    if profile.get("gates") != hard_false_gates():
        fail("profile gates drifted")
    sources = profile.get("sources")
    if (
        not isinstance(sources, list)
        or tuple(item.get("source_id") for item in sources if isinstance(item, dict))
        != SOURCE_IDS
    ):
        fail("physical profile source topology drifted")
    for declaration, source in zip(SOURCE_DECLARATIONS, sources, strict=True):
        if (
            source.get("filename") != declaration[1]
            or source.get("declared_source_url") != declaration[2]
            or source.get("kind") != declaration[3]
        ):
            fail("physical source declaration drifted for " + declaration[0])
        observed = source.get("observed_current")
        if not isinstance(observed, dict):
            fail("observed-current pin is missing for " + declaration[0])
        for key in ("body_bytes", "raw_header_bytes"):
            _exact_int(observed.get(key), declaration[0] + "." + key)
        for key in ("body_sha256", "raw_header_sha256"):
            if not _is_sha256(observed.get(key)):
                fail(declaration[0] + "." + key + " is not SHA-256")
        expected_derivative = source.get("expected_derivative_sha256")
        if not _is_sha256(expected_derivative):
            fail(declaration[0] + " expected derivative hash is malformed")
    logical, hashes = _logical_contract()
    return profile, logical, hashes


def load_profile() -> dict[str, Any]:
    profile, _, _ = _load_profile()
    return parse_json_bytes(canonical_json_bytes(profile), "detached profile")


def _read_observed_directory(root: Path) -> dict[str, bytes]:
    if not isinstance(root, Path) or not root.is_absolute():
        fail("source directory must be an absolute Path")
    absolute = Path(os.path.abspath(os.fspath(root)))
    if absolute != root or absolute.resolve(strict=True) != absolute:
        fail("source directory is not canonical or contains an alias")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(
        os, "O_NOFOLLOW", 0
    )
    directory = os.open(absolute, flags)
    try:
        before_dir = os.fstat(directory)
        if (
            not stat.S_ISDIR(before_dir.st_mode)
            or before_dir.st_uid != os.getuid()
            or before_dir.st_mode & 0o022
        ):
            fail("source directory must be private and owned by the current user")
        expected = tuple(
            name
            for _, filename, _, _ in SOURCE_DECLARATIONS
            for name in (filename, filename + ".headers")
        )
        names = tuple(sorted(os.listdir(directory)))
        if names != tuple(sorted(expected)):
            fail("source directory must contain exactly the twelve frozen files")
        payloads: dict[str, bytes] = {}
        identities: set[tuple[int, int]] = set()
        for name in expected:
            cap = (
                MAX_HEADER_BYTES
                if name.endswith(".headers")
                else MAX_SUSB_BYTES
                if name.endswith(".txt")
                else MAX_AIES_ZIP_BYTES
            )
            descriptor = os.open(
                name,
                os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=directory,
            )
            try:
                before = os.fstat(descriptor)
                identity = (before.st_dev, before.st_ino)
                if (
                    not stat.S_ISREG(before.st_mode)
                    or before.st_nlink != 1
                    or before.st_uid != os.getuid()
                    or before.st_mode & 0o022
                    or before.st_size > cap
                    or identity in identities
                ):
                    fail(name + " is not a distinct safe bounded regular file")
                identities.add(identity)
                chunks: list[bytes] = []
                total = 0
                while True:
                    chunk = os.read(descriptor, min(1024 * 1024, cap + 1 - total))
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > cap:
                        fail(name + " exceeds its byte ceiling")
                    chunks.append(chunk)
                after = os.fstat(descriptor)
                entry = os.stat(name, dir_fd=directory, follow_symlinks=False)
                stable = (
                    "st_dev",
                    "st_ino",
                    "st_mode",
                    "st_nlink",
                    "st_size",
                    "st_mtime_ns",
                    "st_ctime_ns",
                )
                if any(
                    getattr(before, field) != getattr(after, field)
                    or getattr(before, field) != getattr(entry, field)
                    for field in stable
                ):
                    fail(name + " changed during its pinned read")
                payloads[name] = b"".join(chunks)
                if len(payloads[name]) != before.st_size:
                    fail(name + " size changed during its pinned read")
            finally:
                os.close(descriptor)
        after_dir = os.fstat(directory)
        if (
            (before_dir.st_dev, before_dir.st_ino, before_dir.st_mtime_ns)
            != (after_dir.st_dev, after_dir.st_ino, after_dir.st_mtime_ns)
            or tuple(sorted(os.listdir(directory))) != tuple(sorted(expected))
        ):
            fail("source directory changed during snapshot")
        return payloads
    finally:
        os.close(directory)


def _validate_source_fixity(
    source: Mapping[str, Any], body: bytes, header: bytes
) -> dict[str, Any]:
    pin = source["observed_current"]
    if (
        len(body) != pin["body_bytes"]
        or sha256_bytes(body) != pin["body_sha256"]
        or len(header) != pin["raw_header_bytes"]
        or sha256_bytes(header) != pin["raw_header_sha256"]
    ):
        fail(source["source_id"] + " local body/header fixity differs from profile")
    if not header.endswith(b"\r\n\r\n") or b"\n" in header.replace(b"\r\n", b""):
        fail(source["source_id"] + " response header framing drifted")
    try:
        lines = header.decode("ascii").split("\r\n")
    except UnicodeDecodeError as error:
        raise ProfileError("raw response header is not ASCII") from error
    if not lines or lines[0] != "HTTP/2 200 " or lines[-2:] != ["", ""]:
        fail(source["source_id"] + " response status/header block drifted")
    parsed: dict[str, str] = {}
    for line in lines[1:-2]:
        if not line or line[0] in " \t" or ":" not in line:
            fail(source["source_id"] + " response header line is malformed")
        name, value = line.split(":", 1)
        lowered = name.lower()
        if not name or any(
            character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
            for character in name
        ):
            fail(source["source_id"] + " response header name is malformed")
        if lowered in parsed:
            fail(source["source_id"] + " has a duplicate response header")
        parsed[lowered] = value.lstrip(" ")
    response = source["response_diagnostic"]
    for name in (
        "date",
        "content-type",
        "content-length",
        "last-modified",
        "x-content-type-options",
        "cache-control",
        "accept-ranges",
        "strict-transport-security",
        "cf-cache-status",
    ):
        if parsed.get(name) != response[name]:
            fail(source["source_id"] + " response diagnostic field drifted: " + name)
    if int(parsed["content-length"]) != len(body):
        fail(source["source_id"] + " response Content-Length/body size mismatch")
    return {
        "http_status": "HTTP/2 200",
        "date": parsed["date"],
        "content_type": parsed["content-type"],
        "content_length": len(body),
        "last_modified": parsed["last-modified"],
        "raw_header_sha256": sha256_bytes(header),
        "raw_header_bytes": len(header),
        "header_semantics_authenticated": False,
    }


def _is_signed_decimal(value: str, nonnegative: bool = False) -> bool:
    if not value or value[0] == "+":
        return False
    if value[0] == "-":
        if nonnegative:
            return False
        value = value[1:]
    if not value:
        return False
    if value.count(".") > 1:
        return False
    whole, separator, fraction = value.partition(".")
    if not whole and not fraction:
        return False
    return (not whole or all("0" <= c <= "9" for c in whole)) and (
        not separator or fraction != "" and all("0" <= c <= "9" for c in fraction)
    )


def _is_nonnegative_integer(value: str) -> bool:
    return bool(value) and all("0" <= character <= "9" for character in value)


def _framed_digest(row: Mapping[str, str], fields: Sequence[str], tag: bytes) -> bytes:
    digest = hashlib.sha256()
    digest.update(tag)
    for field in fields:
        name = field.encode("utf-8")
        value = row[field].encode("utf-8")
        digest.update(len(name).to_bytes(4, "big"))
        digest.update(name)
        digest.update(len(value).to_bytes(8, "big"))
        digest.update(value)
    return digest.digest()


def _strict_ascii_lines(data: bytes, location: str, expected_lf: int) -> list[str]:
    if (
        data.startswith((b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff"))
        or b"\x00" in data
        or b"\r" in data
        or not data.endswith(b"\n")
        or data.count(b"\n") != expected_lf
    ):
        fail(location + " BOM/NUL/newline contract drifted")
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError as error:
        raise ProfileError(location + " is not ASCII") from error
    lines = text[:-1].split("\n")
    if not lines or any(line == "" for line in lines):
        fail(location + " contains a blank physical line")
    return lines


def _zip_payloads(raw: bytes, source: Mapping[str, Any]) -> dict[str, bytes]:
    if not raw.startswith(b"PK\x03\x04"):
        fail(source["source_id"] + " ZIP has a prefix or bad signature")
    eocd = raw.rfind(b"PK\x05\x06")
    if eocd < 0 or eocd + 22 > len(raw):
        fail(source["source_id"] + " ZIP has no bounded EOCD")
    disk, start_disk, entries_disk, entries_total, _, _, comment = struct.unpack_from(
        "<HHHHIIH", raw, eocd + 4
    )
    if (
        disk != 0
        or start_disk != 0
        or entries_disk != entries_total
        or comment != 0
        or eocd + 22 != len(raw)
        or entries_total != 3
        or b"PK\x06\x06" in raw
        or b"PK\x06\x07" in raw
    ):
        fail(source["source_id"] + " ZIP EOCD/ZIP64/topology drifted")
    try:
        archive = zipfile.ZipFile(io.BytesIO(raw), "r")
    except (zipfile.BadZipFile, OSError) as error:
        raise ProfileError(source["source_id"] + " ZIP is unreadable") from error
    expected = source["layout"]["zip_members"]
    expected_names = tuple(item["name"] for item in expected)
    with archive:
        if archive.comment != b"":
            fail(source["source_id"] + " ZIP archive comment drifted")
        infos = archive.infolist()
        names = tuple(info.filename for info in infos)
        if (
            names != expected_names
            or len(names) != len(set(names))
            or len(names) != len({name.casefold() for name in names})
        ):
            fail(source["source_id"] + " ZIP member topology/order drifted")
        total = 0
        for info, pin in zip(infos, expected, strict=True):
            name = info.filename
            if (
                not name
                or "/" in name
                or "\\" in name
                or "\x00" in name
                or name in (".", "..")
                or info.is_dir()
                or info.create_system != 0
                or info.external_attr != 0
                or info.extra != b""
                or info.comment != b""
                or info.flag_bits != 0x0808
                or info.compress_type != zipfile.ZIP_DEFLATED
                or tuple(info.date_time) != tuple(pin["timestamp"])
                or info.CRC != int(pin["crc32"], 16)
                or info.compress_size != pin["compressed_bytes"]
                or info.file_size != pin["uncompressed_bytes"]
                or info.file_size > MAX_AIES_MEMBER_BYTES
                or info.compress_size == 0
                or info.file_size / info.compress_size > MAX_COMPRESSION_RATIO
            ):
                fail(source["source_id"] + " ZIP member metadata drifted: " + name)
            total += info.file_size
        if total > MAX_AIES_TOTAL_UNCOMPRESSED:
            fail(source["source_id"] + " ZIP expansion ceiling exceeded")
        bad = archive.testzip()
        if bad is not None:
            fail(source["source_id"] + " ZIP CRC failed: " + bad)
        payloads: dict[str, bytes] = {}
        for info, pin in zip(infos, expected, strict=True):
            body = archive.read(info)
            if len(body) != info.file_size or sha256_bytes(body) != pin["sha256"]:
                fail(source["source_id"] + " member body pin drifted: " + info.filename)
            payloads[info.filename] = body
        return payloads


def _mismatch_record(
    code: str, occurrences: list[tuple[int, str, str, str]]
) -> dict[str, Any]:
    ordinal, key, field, raw = occurrences[0]
    return {
        "code": code,
        "occurrence_count": len(occurrences),
        "affected_row_count": len({item[0] for item in occurrences}),
        "first_exemplar": {
            "row_ordinal": ordinal,
            "logical_key": key,
            "field": field,
            "raw_lexeme": raw,
        },
    }


def _parse_aies(
    raw: bytes, source: Mapping[str, Any], logical: Mapping[str, Any]
) -> AIESParsed:
    payloads = _zip_payloads(raw, source)
    product = source["product_code"]
    layout = source["layout"]
    dat_name = product + ".dat"
    fields_name = product + "_FIELDS.txt"
    readme_name = product + "_README.txt"
    dat_lines = _strict_ascii_lines(
        payloads[dat_name], dat_name, layout["lf_counts"]["dat"]
    )
    fields_lines = _strict_ascii_lines(
        payloads[fields_name], fields_name, layout["lf_counts"]["fields"]
    )
    _strict_ascii_lines(
        payloads[readme_name], readme_name, layout["lf_counts"]["readme"]
    )
    if not dat_lines[0].startswith("#") or dat_lines[0].startswith("##"):
        fail(source["source_id"] + " DAT header marker drifted")
    physical_header = dat_lines[0][1:].split("|")
    if physical_header != layout["physical_header"] or len(physical_header) != len(
        set(physical_header)
    ):
        fail(source["source_id"] + " DAT header/order drifted")
    metadata_header = fields_lines[0].split("|")
    if metadata_header != [
        "Field_Name",
        "Label",
        "Field_Type",
        "Field_Length",
        "Number_of_Decimals",
    ]:
        fail(source["source_id"] + " FIELDS header drifted")
    metadata: dict[str, tuple[str, int, int]] = {}
    metadata_names: list[str] = []
    for ordinal, line in enumerate(fields_lines[1:], 1):
        parts = line.split("|")
        if len(parts) != 5 or not parts[0] or not parts[1]:
            fail(source["source_id"] + " malformed FIELDS row")
        name, _, field_type, length, decimals = parts
        if (
            name in metadata
            or field_type not in ("CHARACTER", "NUMBER")
            or not _is_nonnegative_integer(length)
            or not _is_nonnegative_integer(decimals)
            or int(length) < 1
            or int(length) > MAX_FIELD_BYTES
            or int(decimals) > 9
        ):
            fail(source["source_id"] + " invalid FIELDS metadata")
        metadata[name] = (field_type, int(length), int(decimals))
        metadata_names.append(name)
    if metadata_names != physical_header:
        fail(source["source_id"] + " FIELDS sequence does not equal DAT header")
    if len(dat_lines) - 1 != layout["data_rows"] or len(dat_lines) - 1 > MAX_AIES_ROWS:
        fail(source["source_id"] + " DAT row count drifted")
    rows: list[dict[str, str]] = []
    key_seen: set[tuple[str, ...]] = set()
    row_digests: list[bytes] = []
    key_digests: list[bytes] = []
    row_order = hashlib.sha256(b"AIES_LOGICAL_ROW_ORDER_V1")
    blank_counts: Counter[str] = Counter()
    flag_counts: dict[str, Counter[str]] = {
        field: Counter() for field in physical_header if field.endswith("_F")
    }
    mismatch_buckets: dict[str, list[tuple[int, str, str, str]]] = {
        "STRUCTURAL_FLAG_NONEMPTY": [],
        "VALUE_FLAG_OUTSIDE_ACCEPTED_VOCABULARY": [],
        "CV_FLAG_OUTSIDE_ACCEPTED_VOCABULARY": [],
        "NEGATIVE_CV_FORBIDDEN_BY_ACCEPTED_CONTRACT": [],
        "ACCEPTED_DIMENSION_EMPTY": [],
    }
    logical_fields = tuple(logical["logical_fields"])
    key_fields = tuple(logical["key_fields"])
    if "NAME" not in logical_fields or "GEO_LABEL" not in physical_header:
        fail(source["source_id"] + " GEO_LABEL-to-NAME correspondence is absent")
    if any(field != "NAME" and field not in physical_header for field in logical_fields):
        fail(source["source_id"] + " logical field topology is incomplete")
    for ordinal, line in enumerate(dat_lines[1:], 1):
        if '"' in line:
            fail(source["source_id"] + " DAT unexpectedly uses quoting")
        values = line.split("|")
        if len(values) != len(physical_header):
            fail(source["source_id"] + " DAT row width drifted")
        physical = dict(zip(physical_header, values, strict=True))
        for field, value in physical.items():
            encoded = value.encode("ascii")
            if (
                len(encoded) > metadata[field][1]
                or any(ord(character) < 32 for character in value)
                or value.strip() != value
            ):
                fail(source["source_id"] + " DAT field lexical ceiling failed")
            field_type, _, _ = metadata[field]
            if field_type == "NUMBER" and not _is_signed_decimal(value):
                fail(source["source_id"] + " NUMBER field is not exact decimal")
            if value == "":
                blank_counts[field] += 1
            if field in flag_counts:
                flag_counts[field][value] += 1
        projected = {
            field: physical["GEO_LABEL"] if field == "NAME" else physical[field]
            for field in logical_fields
        }
        key = tuple(projected[field] for field in key_fields)
        if key in key_seen:
            fail(source["source_id"] + " has a duplicate accepted logical key")
        key_seen.add(key)
        key_text = "/".join(key)
        for field in logical["structural_flag_fields"]:
            if projected[field] != "":
                mismatch_buckets["STRUCTURAL_FLAG_NONEMPTY"].append(
                    (ordinal, key_text, field, projected[field])
                )
        for field in logical["dimension_fields"]:
            if projected[field] == "":
                mismatch_buckets["ACCEPTED_DIMENSION_EMPTY"].append(
                    (ordinal, key_text, field, "")
                )
        for value_field, flag_field, cv_field, cv_flag_field in zip(
            logical["measure_value_fields"],
            logical["measure_value_flag_fields"],
            logical["measure_cv_fields"],
            logical["measure_cv_flag_fields"],
            strict=True,
        ):
            if projected[flag_field] not in ("", "D", "N", "S", "Z"):
                mismatch_buckets["VALUE_FLAG_OUTSIDE_ACCEPTED_VOCABULARY"].append(
                    (ordinal, key_text, flag_field, projected[flag_field])
                )
            if projected[cv_flag_field] not in ("", "v", "w"):
                mismatch_buckets["CV_FLAG_OUTSIDE_ACCEPTED_VOCABULARY"].append(
                    (ordinal, key_text, cv_flag_field, projected[cv_flag_field])
                )
            if projected[cv_field].startswith("-"):
                mismatch_buckets[
                    "NEGATIVE_CV_FORBIDDEN_BY_ACCEPTED_CONTRACT"
                ].append((ordinal, key_text, cv_field, projected[cv_field]))
            if not _is_signed_decimal(projected[value_field]) or not _is_signed_decimal(
                projected[cv_field]
            ):
                fail(source["source_id"] + " measure lexeme is malformed")
        row_digest = _framed_digest(projected, logical_fields, b"AIES_LOGICAL_ROW_V1")
        key_digest = _framed_digest(projected, key_fields, b"AIES_LOGICAL_KEY_V1")
        row_order.update(row_digest)
        row_digests.append(row_digest)
        key_digests.append(key_digest)
        rows.append(physical)
    mismatches = [
        _mismatch_record(code, occurrences)
        for code, occurrences in mismatch_buckets.items()
        if occurrences
    ]
    incompatible_rows = {
        item[0]
        for occurrences in mismatch_buckets.values()
        for item in occurrences
    }
    public = {
        "physical_format": {
            "encoding": "ASCII",
            "bom_present": False,
            "newline": "LF",
            "terminal_lf": True,
            "delimiter": "|",
            "quoted_fields_present": False,
            "physical_header": physical_header,
            "field_dictionary_order_matches": True,
        },
        "row_count": len(rows),
        "blank_counts": dict(sorted(blank_counts.items())),
        "flag_lexeme_counts": {
            field: dict(sorted(counts.items()))
            for field, counts in sorted(flag_counts.items())
        },
        "logical_field_correspondence": {
            "field_count": len(logical_fields),
            "topology_complete": True,
            "renamed_physical_field": {"GEO_LABEL": "NAME"},
            "dropped_physical_fields": [
                field for field in physical_header if field not in logical_fields and field != "GEO_LABEL"
            ],
            "row_reordering_or_value_normalization_performed": False,
        },
        "logical_projection_row_order_sha256": row_order.hexdigest(),
        "logical_projection_row_membership_sha256": sha256_bytes(
            b"".join(sorted(row_digests))
        ),
        "logical_key_membership_sha256": sha256_bytes(b"".join(sorted(key_digests))),
        "logical_contract_mismatches": mismatches,
        "logical_contract_incompatible_row_count": len(incompatible_rows),
        "logical_contract_compatible": False,
        "provider_flag_semantics_verified": False,
        "physical_flag_lexemes_preserved_without_reclassification": True,
    }
    expected = source["expected_derivative_sha256"]
    actual = sha256_bytes(canonical_json_bytes(public))
    if actual != expected:
        fail(source["source_id"] + " parsed derivative drifted")
    public["derivative_sha256"] = actual
    return AIESParsed(public, tuple(rows), logical)


def _parse_susb(raw: bytes, source: Mapping[str, Any], logical: Mapping[str, Any]) -> dict[str, Any]:
    layout = source["layout"]
    if (
        raw.startswith((b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff"))
        or b"\x00" in raw
        or b"\r" in raw
        or not raw.endswith(b"\n")
        or raw.count(b"\n") != layout["lf_count"]
    ):
        fail("SUSB BOM/NUL/newline contract drifted")
    high_counts = Counter(byte for byte in raw if byte >= 128)
    if high_counts != Counter({0x92: 1324}):
        fail("SUSB Windows-1252 high-byte vocabulary drifted")
    try:
        text = raw.decode("cp1252")
    except UnicodeDecodeError as error:
        raise ProfileError("SUSB is not strict Windows-1252") from error
    if text.encode("cp1252") != raw:
        fail("SUSB Windows-1252 round trip drifted")
    physical_header = layout["physical_header"]
    size_pairs = layout["size_code_map"]
    size_map = {item["physical"]: item["logical"] for item in size_pairs}
    size_labels = {item["physical"]: item["description"] for item in size_pairs}
    physical_order = tuple(item["physical"] for item in size_pairs)
    logical_fields = tuple(logical["logical_fields"])
    key_fields = tuple(logical["key_fields"])
    lines = io.StringIO(text, newline="")
    reader = csv.reader(
        lines,
        delimiter=",",
        quotechar='"',
        doublequote=True,
        strict=True,
    )
    canonical_sink = _HashingTextSink()
    canonical_writer = csv.writer(
        canonical_sink,
        delimiter=",",
        quotechar='"',
        doublequote=True,
        lineterminator="\n",
        quoting=csv.QUOTE_MINIMAL,
    )
    try:
        header = next(reader)
    except StopIteration:
        fail("SUSB is empty")
    if header != physical_header or len(header) != len(set(header)):
        fail("SUSB physical header/order drifted")
    canonical_writer.writerow(header)
    if "EMPLFL_R" in header or [field for field in logical_fields if field not in header] != [
        "EMPLFL_R"
    ]:
        fail("SUSB physical/logical field correspondence drifted")
    row_count = 0
    keys_seen: set[tuple[str, ...]] = set()
    groups_seen: set[tuple[str, str]] = set()
    current_group: tuple[str, str] | None = None
    current_rows: dict[str, dict[str, str]] = {}
    current_sequence: list[str] = []
    row_order = hashlib.sha256(b"SUSB_PROVISIONAL_LOGICAL_ROW_ORDER_V1")
    row_digests: list[bytes] = []
    key_digests: list[bytes] = []
    projection = hashlib.sha256(b"SUSB_NATIONAL_01_PROJECTION_V1")
    projection_count = 0
    size_counts: Counter[str] = Counter()
    group_size_counts: Counter[str] = Counter()
    membership_patterns: Counter[str] = Counter()
    state_values: set[str] = set()
    naics_values: set[str] = set()
    flag_counts: dict[str, Counter[str]] = {
        "EMPLFL_N": Counter(),
        "PAYRFL_N": Counter(),
        "RCPTFL_N": Counter(),
    }
    physical_identities: dict[str, Counter[str]] = {
        "05=02+03+04": Counter(),
        "08=05+06+07": Counter(),
        "01=08+09": Counter(),
        "01=02+03+04+06+07+09": Counter(),
    }
    accepted_identities: dict[str, Counter[str]] = {
        identity: Counter() for identity in physical_identities
    }
    first_incomplete: tuple[str, str, tuple[str, ...]] | None = None

    def flush_group() -> None:
        nonlocal first_incomplete
        if current_group is None:
            return
        sequence = tuple(current_sequence)
        indices = tuple(physical_order.index(code) for code in sequence)
        if indices != tuple(sorted(indices)) or len(sequence) != len(set(sequence)):
            fail("SUSB size rows are not a strict physical-order subsequence")
        logical_sequence = tuple(size_map[code] for code in sequence)
        membership_patterns["|".join(logical_sequence)] += 1
        group_size_counts[str(len(sequence))] += 1
        if len(sequence) != 9 and first_incomplete is None:
            first_incomplete = (current_group[0], current_group[1], logical_sequence)
        equations = (
            ("05=02+03+04", "05", ("02", "03", "04")),
            ("08=05+06+07", "08", ("05", "06", "07")),
            ("01=08+09", "01", ("08", "09")),
            (
                "01=02+03+04+06+07+09",
                "01",
                ("02", "03", "04", "06", "07", "09"),
            ),
        )
        for identity, left, right in equations:
            if left not in current_rows or any(code not in current_rows for code in right):
                continue
            for metric in ("FIRM", "ESTB", "EMPL", "PAYR", "RCPT"):
                ok = int(current_rows[left][metric]) == sum(
                    int(current_rows[code][metric]) for code in right
                )
                physical_identities[identity][metric + "_participants"] += 1
                physical_identities[identity][metric + ("_pass" if ok else "_FAIL")] += 1
                flag_field = {
                    "EMPL": "EMPLFL_N",
                    "PAYR": "PAYRFL_N",
                    "RCPT": "RCPTFL_N",
                }.get(metric)
                eligible = flag_field is None or all(
                    current_rows[code][flag_field] == ""
                    for code in (left,) + right
                )
                accepted_identities[identity][
                    metric + ("_eligible" if eligible else "_unverifiable_noise_flag")
                ] += 1
                if eligible:
                    accepted_identities[identity][
                        metric + ("_pass" if ok else "_FAIL")
                    ] += 1
                if not ok:
                    fail("SUSB physical arithmetic identity failed: " + identity)

    for raw_row in reader:
        row_count += 1
        if row_count > MAX_SUSB_ROWS or len(raw_row) != len(header):
            fail("SUSB row count/width ceiling failed")
        canonical_writer.writerow(raw_row)
        physical = dict(zip(header, raw_row, strict=True))
        for field, value in physical.items():
            if (
                value == ""
                or len(value.encode("cp1252")) > MAX_FIELD_BYTES
                or value.strip() != value
                or any(ord(character) < 32 for character in value)
            ):
                fail("SUSB blank/control/field-size contract drifted")
        if (
            not len(physical["STATE"]) == 2
            or not _is_nonnegative_integer(physical["STATE"])
            or physical["ENTRSIZE"] not in size_map
            or physical["ENTRSIZEDSCR"] != size_labels[physical["ENTRSIZE"]]
            or any(
                not _is_nonnegative_integer(physical[field])
                for field in ("FIRM", "ESTB", "EMPL", "PAYR", "RCPT")
            )
            or any(physical[field] not in ("G", "H", "J") for field in flag_counts)
        ):
            fail("SUSB dimension, integer, size-map, or flag lexeme drifted")
        pair = (physical["STATE"], physical["NAICS"])
        if current_group is None:
            current_group = pair
        elif pair != current_group:
            flush_group()
            groups_seen.add(current_group)
            if pair in groups_seen:
                fail("SUSB STATE/NAICS group is noncontiguous")
            current_group = pair
            current_rows = {}
            current_sequence = []
        logical_size = size_map[physical["ENTRSIZE"]]
        projected = {
            field: ""
            if field == "EMPLFL_R"
            else logical_size
            if field == "ENTRSIZE"
            else physical[field]
            for field in logical_fields
        }
        key = tuple(projected[field] for field in key_fields)
        if key in keys_seen:
            fail("SUSB has a duplicate provisional logical key")
        keys_seen.add(key)
        current_rows[logical_size] = projected
        current_sequence.append(physical["ENTRSIZE"])
        state_values.add(physical["STATE"])
        naics_values.add(physical["NAICS"])
        size_counts[logical_size] += 1
        for field in flag_counts:
            flag_counts[field][physical[field]] += 1
        row_digest = _framed_digest(
            projected, logical_fields, b"SUSB_PROVISIONAL_LOGICAL_ROW_V1"
        )
        key_digest = _framed_digest(
            projected, key_fields, b"SUSB_PROVISIONAL_LOGICAL_KEY_V1"
        )
        row_order.update(row_digest)
        row_digests.append(row_digest)
        key_digests.append(key_digest)
        if physical["STATE"] == "00" and logical_size == "01":
            projection.update(row_digest)
            projection_count += 1
    flush_group()
    if current_group is not None:
        groups_seen.add(current_group)
    if row_count != layout["data_rows"]:
        fail("SUSB data row count drifted")
    if (
        canonical_sink.byte_count != len(raw)
        or canonical_sink.digest.hexdigest() != sha256_bytes(raw)
    ):
        fail("SUSB CSV is not canonical minimal-quote Windows-1252")
    complete_groups = group_size_counts["9"]
    incomplete_groups = len(groups_seen) - complete_groups
    mismatch = [
        {
            "code": "PHYSICAL_EMPLFL_R_COLUMN_ABSENT",
            "occurrence_count": 1,
            "affected_row_count": row_count,
            "first_exemplar": {
                "row_ordinal": 0,
                "logical_key": "HEADER",
                "field": "EMPLFL_R",
                "raw_lexeme": "PHYSICAL_COLUMN_ABSENT",
            },
        },
        {
            "code": "PHYSICAL_SIZE_CODE_LEXEME_DIFFERS_FROM_LOGICAL_CODE",
            "occurrence_count": sum(
                size_counts[item["logical"]]
                for item in size_pairs
                if item["physical"] != item["logical"]
            ),
            "affected_row_count": sum(
                size_counts[item["logical"]]
                for item in size_pairs
                if item["physical"] != item["logical"]
            ),
            "first_exemplar": {
                "row_ordinal": 4,
                "logical_key": "00/--/04",
                "field": "ENTRSIZE",
                "raw_lexeme": "26",
            },
        },
        {
            "code": "STATE_NAICS_GROUP_MISSING_LOGICAL_SIZE_ROWS",
            "occurrence_count": incomplete_groups,
            "affected_row_count": incomplete_groups,
            "first_exemplar": {
                "row_ordinal": 0,
                "logical_key": first_incomplete[0] + "/" + first_incomplete[1],
                "field": "ENTRSIZE",
                "raw_lexeme": "|".join(first_incomplete[2]),
            },
        },
    ]
    patterns_hash = sha256_bytes(
        canonical_json_bytes(dict(sorted(membership_patterns.items())))
    )
    public = {
        "physical_format": {
            "encoding": "WINDOWS-1252",
            "utf8_compatible": False,
            "non_ascii_byte_counts": {"92": 1324},
            "bom_present": False,
            "newline": "LF",
            "terminal_lf": True,
            "delimiter": ",",
            "quote_mode": "CSV_MINIMAL",
            "quote_byte_count": raw.count(b'"'),
            "quoted_physical_line_count": sum(
                1 for line in io.BytesIO(raw) if b'"' in line
            ),
            "physical_header": physical_header,
            "physical_emplfl_r_present": False,
        },
        "row_count": row_count,
        "state_count": len(state_values),
        "naics_lexeme_count": len(naics_values),
        "state_naics_group_count": len(groups_seen),
        "group_size_count_distribution": dict(sorted(group_size_counts.items())),
        "complete_nine_size_group_count": complete_groups,
        "incomplete_size_group_count": incomplete_groups,
        "size_row_counts": dict(sorted(size_counts.items())),
        "membership_pattern_count": len(membership_patterns),
        "membership_pattern_counts_sha256": patterns_hash,
        "flag_lexeme_counts": {
            field: dict(sorted(counts.items()))
            for field, counts in sorted(flag_counts.items())
        },
        "provisional_logical_row_order_sha256": row_order.hexdigest(),
        "provisional_logical_row_membership_sha256": sha256_bytes(
            b"".join(sorted(row_digests))
        ),
        "provisional_logical_key_membership_sha256": sha256_bytes(
            b"".join(sorted(key_digests))
        ),
        "national_state_00_size_01_projection": {
            "row_count": projection_count,
            "sha256": projection.hexdigest(),
            "separately_hashed": True,
            "admitted_logical_table": False,
        },
        "physical_arithmetic_identities": {
            identity: dict(sorted(counts.items()))
            for identity, counts in physical_identities.items()
        },
        "accepted_contract_identity_semantics": {
            identity: dict(sorted(counts.items()))
            for identity, counts in accepted_identities.items()
        },
        "logical_field_correspondence": {
            "field_count": len(logical_fields),
            "topology_complete_only_after_absent_emplfl_r_insertion": True,
            "physical_to_logical_size_map": size_pairs,
            "missing_size_rows_synthesized": False,
            "physical_lexemes_preserved": True,
        },
        "logical_contract_mismatches": mismatch,
        "logical_contract_compatible": False,
        "firm_cross_naics_sum_performed": False,
        "firm_model_role": (
            "INDUSTRY_FIRM_PRESENCES_PROXY_ONLY_PENDING_VALIDATED_"
            "ALLOCATION_OR_DEDUPLICATION_ONTOLOGY"
        ),
    }
    expected = source["expected_derivative_sha256"]
    actual = sha256_bytes(canonical_json_bytes(public))
    if actual != expected:
        fail(source["source_id"] + " parsed derivative drifted")
    public["derivative_sha256"] = actual
    return public


def _cross_aies(parsed: Mapping[str, AIESParsed]) -> dict[str, Any]:
    economy = parsed[SOURCE_IDS[0]]
    economy_index: dict[tuple[str, str, str, str], dict[str, str]] = {}
    for row in economy.rows:
        key = (row["SECTOR"], row["NAICS"], row["TYPOP"], row["TAXSTAT"])
        if key in economy_index:
            fail("AIES00 cross-file comparison key is duplicate")
        economy_index[key] = row
    matches: dict[str, dict[str, int]] = {}
    for source_id in SOURCE_IDS[1:5]:
        candidate = parsed[source_id]
        compared = 0
        exact = 0
        for row in candidate.rows:
            key = (
                row["SECTOR"],
                row["NAICS"],
                row.get("TYPOP", "00"),
                row.get("TAXSTAT", "00"),
            )
            parent = economy_index.get(key)
            compared += 1
            if parent is not None and all(
                row[field] == parent[field]
                for field in (
                    "INV_E_TOT_DVAL",
                    "INV_E_TOT_DVAL_F",
                    "INV_E_TOT_CV",
                    "INV_E_TOT_CV_F",
                )
            ):
                exact += 1
        if exact != compared:
            fail(source_id + " total inventory does not project exactly to AIES00")
        matches[source_id] = {"compared_rows": compared, "exact_matches": exact}
    return {
        "detail_total_inventory_to_aies00": matches,
        "all_detail_rows_match_exactly": True,
        "aies51_component_additivity_required": False,
    }


def _finalize(result: dict[str, Any]) -> dict[str, Any]:
    if "content_sha256" in result:
        fail("result is already finalized")
    result["content_sha256"] = sha256_bytes(canonical_json_bytes(result))
    return result


def parse_observed_directory(source_directory: Path) -> dict[str, Any]:
    """Parse exactly the frozen 12-file present-day directory."""

    profile, logical_contract, logical_hashes = _load_profile()
    payloads = _read_observed_directory(source_directory)
    logical_by_id = {
        item["profile_id"]: item for item in logical_contract["profiles"]
    }
    sources_by_id = {item["source_id"]: item for item in profile["sources"]}
    records: list[dict[str, Any]] = []
    parsed_aies: dict[str, AIESParsed] = {}
    for source_id in SOURCE_IDS:
        source = sources_by_id[source_id]
        filename = source["filename"]
        body = payloads[filename]
        header = payloads[filename + ".headers"]
        response = _validate_source_fixity(source, body, header)
        logical = logical_by_id[source_id]
        if source["kind"] == "aies_zip":
            parsed = _parse_aies(body, source, logical)
            parsed_aies[source_id] = parsed
            diagnostic = parsed.public
        else:
            diagnostic = _parse_susb(body, source, logical)
        records.append(
            {
                "source_id": source_id,
                "declared_source_url": source["declared_source_url"],
                "local_body_sha256": sha256_bytes(body),
                "local_body_bytes": len(body),
                "local_body_hash_and_size_verified": True,
                "local_raw_header_hash_and_size_verified": True,
                "declared_source_url_matches_frozen_contract": True,
                "local_body_to_declared_url_provenance_verified": False,
                "provider_provenance_verified": False,
                "transport_authenticated": False,
                "custody_verified": False,
                "response_diagnostic": response,
                "physical_diagnostic": diagnostic,
                "gates": hard_false_gates(),
            }
        )
    cross = _cross_aies(parsed_aies)
    expected_cross = profile["cross_source"]["expected_derivative_sha256"]
    actual_cross = sha256_bytes(canonical_json_bytes(cross))
    if actual_cross != expected_cross:
        fail("cross-source derivative drifted")
    cross["derivative_sha256"] = actual_cross
    result = {
        "schema_version": SCHEMA_VERSION,
        "status": STATUS,
        "role": ROLE,
        "canonicalization": CANONICALIZATION,
        "mode": "FROZEN_PRESENT_DAY_EXTERNAL_DIRECTORY",
        "profile_physical_sha256": EXPECTED_PROFILE_PHYSICAL_SHA256,
        "profile_semantic_sha256": profile["artifact"]["content_sha256"],
        "logical_contract_physical_sha256": (
            EXPECTED_LOGICAL_PROFILE_PHYSICAL_SHA256
        ),
        "logical_contract_semantic_sha256": (
            EXPECTED_LOGICAL_PROFILE_SEMANTIC_SHA256
        ),
        "logical_contract_artifact_hashes": logical_hashes,
        "source_count": len(records),
        "exact_six_source_topology_verified": True,
        "source_verification_performed": True,
        "source_verification_kind": (
            "FROZEN_LOCAL_BODY_AND_RAW_HEADER_SHA256_SIZE_FIXITY_"
            "NONAUTHENTICATING"
        ),
        "present_day_only": True,
        "logical_field_topology_mapped": True,
        "logical_constraint_compatibility": False,
        "logical_contract_successor_required_before_qualification": True,
        "provider_flag_semantics_verified": False,
        "body_to_url_provenance_claimed": False,
        "future_compatibility_claimed": False,
        "self_accepted": False,
        "independent_audit_required": True,
        "records": records,
        "cross_source": cross,
        "gates": hard_false_gates(),
    }
    return _finalize(result)


def _validate_result_shape(result: Mapping[str, Any]) -> None:
    if (
        result.get("status") != STATUS
        or result.get("role") != ROLE
        or type(result.get("source_count")) is not int
        or result.get("source_count") != 6
        or result.get("source_verification_performed") is not True
        or result.get("logical_constraint_compatibility") is not False
        or result.get("body_to_url_provenance_claimed") is not False
        or result.get("future_compatibility_claimed") is not False
        or result.get("self_accepted") is not False
        or result.get("gates") != hard_false_gates()
    ):
        fail("result ceiling, typing, or topology drifted")
    records = result.get("records")
    if (
        not isinstance(records, list)
        or tuple(item.get("source_id") for item in records if isinstance(item, dict))
        != SOURCE_IDS
    ):
        fail("result source topology drifted")
    for record in records:
        if (
            record.get("gates") != hard_false_gates()
            or record.get("local_body_hash_and_size_verified") is not True
            or record.get("local_raw_header_hash_and_size_verified") is not True
            or record.get("local_body_to_declared_url_provenance_verified")
            is not False
            or record.get("provider_provenance_verified") is not False
        ):
            fail("result source claim ceiling drifted")
    content_hash = result.get("content_sha256")
    if not _is_sha256(content_hash):
        fail("result content hash is malformed")
    copy = parse_json_bytes(canonical_json_bytes(result), "result copy")
    del copy["content_sha256"]
    if sha256_bytes(canonical_json_bytes(copy)) != content_hash:
        fail("result self-hash does not verify")


def validate_observed_result_bytes(
    result_bytes: bytes, source_directory: Path
) -> dict[str, Any]:
    """Type-exactly replay an observed result from all twelve source files."""

    result = parse_json_bytes(result_bytes, "observed result")
    if result_bytes != canonical_json_bytes(result):
        fail("observed result bytes are not exact canonical JSON")
    _validate_result_shape(result)
    rebuilt = parse_observed_directory(source_directory)
    if canonical_json_bytes(result) != canonical_json_bytes(rebuilt):
        fail("observed result does not replay exactly from frozen sources")
    return result


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-directory", required=True)
    arguments = parser.parse_args(argv)
    try:
        result = parse_observed_directory(Path(arguments.source_directory))
    except (ProfileError, OSError, csv.Error, zipfile.BadZipFile) as error:
        print("CANNOT_RUN: " + str(error), file=sys.stderr)
        return 2
    sys.stdout.buffer.write(canonical_json_bytes(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
