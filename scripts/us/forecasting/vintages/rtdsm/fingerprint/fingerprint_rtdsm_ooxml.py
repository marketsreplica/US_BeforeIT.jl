#!/usr/bin/env python3
"""Fingerprint five RTDSM quarterly matrices without reproducing their grids.

The output is a compact research diagnostic.  It is not an admissible
forecast origin, truth artifact, model input, or redistribution of RTDSM.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import posixpath
import re
import stat
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP, localcontext
from pathlib import Path, PurePosixPath
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple
from xml.etree import ElementTree as ET

sys.dont_write_bytecode = True

SCHEMA_VERSION = "beforeit-us-rtdsm-quarterly-fingerprint.v1"
GENERATOR_VERSION = "beforeit-us-rtdsm-quarterly-ooxml-parser.v1"
STATUS = "RTDSM_PRESENT_DAY_RESEARCH_DIAGNOSTIC_NONADMITTING"
CANONICALIZATION = "utf8_sorted_keys_compact_json_lf"
EXPECTED_PROFILE_SHA256 = (
    "6eb3a722dc6cfed72f16782f6f065a85de1bc0a3b2c1b733695c6338db1b593c"
)
EXPECTED_RAW_NAMES = {
    "NOUTPUTQvQd.xlsx",
    "ROUTPUTQvQd.xlsx",
    "PQvQd.xlsx",
    "pconQvQd.xlsx",
    "PCONXQvQd.xlsx",
}
EXPECTED_CROSSCHECK_REFERENCE_PERIODS = ("2019Q4", "2021Q2")
RAW_BUNDLE_DOMAIN = (
    "beforeit-us-rtdsm-quarterly-five-file-bundle-sha256.v1"
)
USED_PROVENANCE_RELATION = "used"
USED_PROVENANCE_ROLE = "selected_release_semantic_crosscheck"
OTHER_PROVENANCE_POLICY = (
    "OTHER_DOCUMENTED_REQUIRES_REASON_SOURCE_URL_AND_OPERATOR_NOTE"
)
UNKNOWN_PROVENANCE_POLICY = (
    "UNKNOWN_IS_NEVER_COERCED_TO_ZERO_FALSE_AVAILABLE_OR_UNAVAILABLE"
)
MAX_ZIP_MEMBERS = 128
MAX_MEMBER_BYTES = 50_000_000
MAX_TOTAL_UNCOMPRESSED_BYTES = 100_000_000
MAX_COMPRESSION_RATIO = Decimal("100")
MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
DOC_REL_NS = (
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
)
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
MAIN = "{" + MAIN_NS + "}"
DOC_REL = "{" + DOC_REL_NS + "}"
PKG_REL = "{" + PKG_REL_NS + "}"
HASH_RE = re.compile(r"[0-9a-f]{64}\Z")
CELL_RE = re.compile(r"([A-Z]+)([1-9][0-9]*)\Z")
REFERENCE_RE = re.compile(r"([0-9]{4}):Q([1-4])\Z")
CANONICAL_QUARTER_RE = re.compile(r"([0-9]{4})Q([1-4])\Z")
DECIMAL_RE = re.compile(r"-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\Z")
FORBIDDEN_ZIP_COMPONENTS = (
    "vbaproject",
    "activex",
    "embeddings/",
    "oleobjects/",
    "externallinks/",
    "connections",
)


class FingerprintError(RuntimeError):
    """Raised when source bytes or semantic bindings fail closed."""


@dataclass(frozen=True)
class SeriesSpec:
    series_id: str
    filename: str
    sheet_name: str
    header_prefix: str
    first_supported_vintage: str
    source_semantics: str
    protocol_mapping: str
    mapping_status: str
    forbidden_direct_mapping: bool


@dataclass
class ParsedPanel:
    spec: SeriesSpec
    raw_sha256: str
    raw_byte_count: int
    member_manifest_sha256: str
    relationship_manifest_sha256: str
    worksheet_xml_sha256: str
    shared_strings_semantic_sha256: str
    styles_semantic_sha256: str
    sheet_name: str
    worksheet_dimension: str
    physical_row_element_count: int
    trailing_empty_row_element_count: int
    vintage_start: str
    vintage_end: str
    vintage_count: int
    reference_period_start: str
    reference_period_end: str
    reference_period_count: int
    numeric_cell_count: int
    source_missing_marker_count: int
    structural_future_cell_count: int
    unknown_absent_cell_count: int
    unknown_unsupported_token_count: int
    semantic_grid_sha256: str
    layout_manifest_sha256: str
    selected: Dict[Tuple[str, str], Dict[str, Any]]

    def compact_record(self) -> Dict[str, Any]:
        return {
            "series_id": self.spec.series_id,
            "filename": self.spec.filename,
            "raw_sha256": self.raw_sha256,
            "raw_byte_count": self.raw_byte_count,
            "zip_member_manifest_sha256": self.member_manifest_sha256,
            "workbook_relationship_manifest_sha256": (
                self.relationship_manifest_sha256
            ),
            "worksheet_xml_sha256": self.worksheet_xml_sha256,
            "shared_strings_semantic_sha256": (
                self.shared_strings_semantic_sha256
            ),
            "styles_semantic_sha256": self.styles_semantic_sha256,
            "sheet_name": self.sheet_name,
            "worksheet_dimension": self.worksheet_dimension,
            "physical_row_element_count": self.physical_row_element_count,
            "trailing_empty_row_element_count": (
                self.trailing_empty_row_element_count
            ),
            "source_semantics": self.spec.source_semantics,
            "protocol_mapping": self.spec.protocol_mapping,
            "mapping_status": self.spec.mapping_status,
            "forbidden_direct_mapping": self.spec.forbidden_direct_mapping,
            "vintage_start": self.vintage_start,
            "vintage_end": self.vintage_end,
            "vintage_count": self.vintage_count,
            "reference_period_start": self.reference_period_start,
            "reference_period_end": self.reference_period_end,
            "reference_period_count": self.reference_period_count,
            "numeric_cell_count": self.numeric_cell_count,
            "source_missing_marker_count": self.source_missing_marker_count,
            "structural_future_cell_count": self.structural_future_cell_count,
            "unknown_absent_cell_count": self.unknown_absent_cell_count,
            "unknown_unsupported_token_count": (
                self.unknown_unsupported_token_count
            ),
            "semantic_grid_sha256": self.semantic_grid_sha256,
            "layout_manifest_sha256": self.layout_manifest_sha256,
            "gates": hard_false_gates(),
        }


def hard_false_gates() -> Dict[str, bool]:
    return {
        "historical_availability_verified": False,
        "intraday_availability_verified": False,
        "strict_origin_admissible": False,
        "truth_admissible": False,
        "model_input_allowed": False,
        "empirical_execution_allowed": False,
        "inventory_mutation_authorized": False,
        "production_authorized": False,
        "ready": False,
    }


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _update_length_prefixed_field(
    digest: "hashlib._Hash",
    name: str,
    value: Any,
) -> None:
    for item in (name, str(value)):
        data = item.encode("utf-8")
        digest.update(str(len(data)).encode("ascii"))
        digest.update(b":")
        digest.update(data)


def raw_bundle_sha256(
    profile: Mapping[str, Any],
    panels: Sequence[ParsedPanel],
) -> str:
    records = profile.get("series")
    if not isinstance(records, list) or len(records) != len(panels):
        raise FingerprintError("raw bundle profile/panel cardinality drifted")
    digest = hashlib.sha256()
    _update_length_prefixed_field(digest, "domain", RAW_BUNDLE_DOMAIN)
    _update_length_prefixed_field(
        digest,
        "profile_sha256",
        EXPECTED_PROFILE_SHA256,
    )
    _update_length_prefixed_field(
        digest,
        "dataset_id",
        _required_text(profile, "dataset_id"),
    )
    for index, (record, panel) in enumerate(zip(records, panels), start=1):
        if not isinstance(record, dict):
            raise FingerprintError("raw bundle series record is malformed")
        if _required_text(record, "series_id") != panel.spec.series_id:
            raise FingerprintError("raw bundle series order drifted")
        _update_length_prefixed_field(digest, "matrix_index", index)
        _update_length_prefixed_field(
            digest,
            "series_id",
            panel.spec.series_id,
        )
        _update_length_prefixed_field(
            digest,
            "filename",
            panel.spec.filename,
        )
        _update_length_prefixed_field(
            digest,
            "canonical_url",
            _required_text(record, "canonical_url"),
        )
        _update_length_prefixed_field(
            digest,
            "raw_sha256",
            panel.raw_sha256,
        )
        _update_length_prefixed_field(
            digest,
            "raw_byte_count",
            panel.raw_byte_count,
        )
    return digest.hexdigest()


def _reject_duplicate_keys(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise FingerprintError("duplicate JSON key: " + key)
        result[key] = value
    return result


def parse_json_bytes(data: bytes, location: str) -> Dict[str, Any]:
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_keys,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FingerprintError(location + " is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise FingerprintError(location + " must contain an object")
    return value


def _selected_crosscheck_records(
    profile: Mapping[str, Any],
) -> Tuple[Dict[str, str], ...]:
    records = profile.get("selected_crosschecks")
    if not isinstance(records, list) or len(records) != 2:
        raise FingerprintError("selected cross-check profile drifted")
    selected: List[Dict[str, str]] = []
    for index, record in enumerate(records, start=1):
        location = f"selected cross-check profile record {index}"
        if not isinstance(record, dict):
            raise FingerprintError(f"{location} is malformed")
        if set(record) != {
            "reference_period",
            "rtdsm_vintage",
            "bea_fingerprint_sha256",
            "bea_annual_update_caveat",
        }:
            raise FingerprintError(f"{location} keys drifted")
        selected_record = {
            key: _required_text(record, key)
            for key in (
                "reference_period",
                "rtdsm_vintage",
                "bea_fingerprint_sha256",
                "bea_annual_update_caveat",
            )
        }
        if (
            CANONICAL_QUARTER_RE.fullmatch(selected_record["reference_period"])
            is None
            or CANONICAL_QUARTER_RE.fullmatch(selected_record["rtdsm_vintage"])
            is None
        ):
            raise FingerprintError(f"{location} has a malformed quarter")
        if (
            HASH_RE.fullmatch(selected_record["bea_fingerprint_sha256"])
            is None
        ):
            raise FingerprintError(f"{location} has a malformed BEA fingerprint")
        selected.append(selected_record)
    if tuple(record["reference_period"] for record in selected) != (
        EXPECTED_CROSSCHECK_REFERENCE_PERIODS
    ):
        raise FingerprintError("selected cross-check profile period order drifted")
    if len(
        {record["bea_fingerprint_sha256"] for record in selected}
    ) != len(selected):
        raise FingerprintError(
            "selected cross-check profile BEA fingerprints are not unique"
        )
    return tuple(selected)


def load_profile(path: Path) -> Tuple[Dict[str, Any], List[SeriesSpec]]:
    if not path.is_absolute() or path.is_symlink():
        raise FingerprintError("profile path is unsafe")
    resolved = path.resolve(strict=True)
    if not resolved.is_file() or resolved != path:
        raise FingerprintError("profile path is unsafe")
    data = path.read_bytes()
    if sha256_bytes(data) != EXPECTED_PROFILE_SHA256:
        raise FingerprintError("RTDSM source profile SHA-256 drifted")
    profile = parse_json_bytes(data, "RTDSM source profile")
    if profile.get("schema_version") != (
        "beforeit-us-rtdsm-quarterly-source-profile.v1"
    ):
        raise FingerprintError("RTDSM source profile schema drifted")
    records = profile.get("series")
    if not isinstance(records, list) or len(records) != 5:
        raise FingerprintError("RTDSM source profile must contain five series")
    specs: List[SeriesSpec] = []
    for record in records:
        if not isinstance(record, dict):
            raise FingerprintError("RTDSM series profile is malformed")
        specs.append(
            SeriesSpec(
                series_id=_required_text(record, "series_id"),
                filename=_required_text(record, "filename"),
                sheet_name=_required_text(record, "sheet_name"),
                header_prefix=_required_text(record, "header_prefix"),
                first_supported_vintage=_required_text(
                    record,
                    "first_supported_vintage",
                ),
                source_semantics=_required_text(record, "source_semantics"),
                protocol_mapping=_required_text(record, "protocol_mapping"),
                mapping_status=_required_text(record, "mapping_status"),
                forbidden_direct_mapping=bool(
                    record.get("forbidden_direct_mapping", False)
                ),
            )
        )
    if {spec.filename for spec in specs} != EXPECTED_RAW_NAMES:
        raise FingerprintError("RTDSM source filename set drifted")
    if [spec.series_id for spec in specs] != [
        "NOUTPUT",
        "ROUTPUT",
        "P",
        "PCON",
        "PCONX",
    ]:
        raise FingerprintError("RTDSM source order drifted")
    if {
        spec.series_id
        for spec in specs
        if spec.forbidden_direct_mapping
    } != {"P", "PCON"}:
        raise FingerprintError("mandatory concept-mismatch set drifted")
    _selected_crosscheck_records(profile)
    return profile, specs


def _required_text(record: Mapping[str, Any], key: str) -> str:
    value = record.get(key)
    if not isinstance(value, str) or not value:
        raise FingerprintError(key + " must be nonempty text")
    return value


def quarter_index(value: str) -> int:
    match = CANONICAL_QUARTER_RE.fullmatch(value)
    if match is None:
        raise FingerprintError("malformed canonical quarter: " + value)
    return int(match.group(1)) * 4 + int(match.group(2)) - 1


def quarter_text(index: int) -> str:
    return "{}Q{}".format(index // 4, index % 4 + 1)


def canonical_reference(value: str) -> str:
    match = REFERENCE_RE.fullmatch(value)
    if match is None:
        raise FingerprintError("malformed RTDSM reference period: " + value)
    return "{}Q{}".format(match.group(1), match.group(2))


def excel_column_number(letters: str) -> int:
    result = 0
    for character in letters:
        result = result * 26 + ord(character) - ord("A") + 1
    return result


def excel_column_letters(number: int) -> str:
    if number <= 0:
        raise FingerprintError("Excel column number must be positive")
    result = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        result = chr(ord("A") + remainder) + result
    return result


def split_cell_reference(value: str) -> Tuple[int, int]:
    match = CELL_RE.fullmatch(value)
    if match is None:
        raise FingerprintError("malformed cell reference: " + value)
    return excel_column_number(match.group(1)), int(match.group(2))


def decimal_text(value: Decimal) -> str:
    if not value.is_finite():
        raise FingerprintError("derived decimal is non-finite")
    if value.is_zero():
        return "0"
    text = format(value, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text


def parse_decimal(value: str, location: str) -> Decimal:
    if DECIMAL_RE.fullmatch(value) is None:
        raise FingerprintError(location + " is not a canonical decimal")
    try:
        result = Decimal(value)
    except InvalidOperation as error:
        raise FingerprintError(location + " is not a decimal") from error
    if not result.is_finite():
        raise FingerprintError(location + " is not finite")
    return result


def _xml_root(data: bytes, location: str) -> ET.Element:
    upper = data[:4096].upper()
    if b"<!DOCTYPE" in upper or b"<!ENTITY" in upper:
        raise FingerprintError(location + " contains a forbidden declaration")
    try:
        return ET.fromstring(data)
    except ET.ParseError as error:
        raise FingerprintError(location + " is malformed XML") from error


def _read_pinned_regular_file(path: Path) -> bytes:
    if not path.is_absolute():
        raise FingerprintError("raw workbook path must be absolute")
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise FingerprintError("raw workbook path is unsafe: " + path.name) from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise FingerprintError(
                "raw workbook must be a single-link regular file: " + path.name
            )
        chunks: List[bytes] = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        path_metadata = os.stat(path, follow_symlinks=False)
        after = os.fstat(descriptor)
        if (
            not stat.S_ISREG(path_metadata.st_mode)
            or path_metadata.st_nlink != 1
            or (path_metadata.st_dev, path_metadata.st_ino)
            != (metadata.st_dev, metadata.st_ino)
            or (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
            != (
                metadata.st_dev,
                metadata.st_ino,
                metadata.st_size,
                metadata.st_mtime_ns,
            )
        ):
            raise FingerprintError(
                "raw workbook changed during pinned read: " + path.name
            )
        data = b"".join(chunks)
        if len(data) != metadata.st_size:
            raise FingerprintError("raw workbook size changed during read")
        return data
    finally:
        os.close(descriptor)


def _safe_zip(raw_bytes: bytes) -> Tuple[zipfile.ZipFile, Dict[str, bytes], str]:
    archive = zipfile.ZipFile(io.BytesIO(raw_bytes), "r")
    infos = archive.infolist()
    names = [info.filename for info in infos]
    if len(infos) == 0 or len(infos) > MAX_ZIP_MEMBERS:
        archive.close()
        raise FingerprintError("ZIP member count is outside bounds")
    if len(names) != len(set(names)):
        archive.close()
        raise FingerprintError("ZIP contains duplicate member names")
    total = 0
    for info in infos:
        pure = PurePosixPath(info.filename)
        lowered = info.filename.lower()
        if (
            info.filename.startswith("/")
            or "\\" in info.filename
            or ".." in pure.parts
            or any(component in lowered for component in FORBIDDEN_ZIP_COMPONENTS)
        ):
            archive.close()
            raise FingerprintError("ZIP contains an unsafe member")
        if info.flag_bits & 0x1:
            archive.close()
            raise FingerprintError("ZIP contains an encrypted member")
        unix_mode = (info.external_attr >> 16) & 0xFFFF
        if unix_mode and stat.S_ISLNK(unix_mode):
            archive.close()
            raise FingerprintError("ZIP contains a symbolic-link member")
        if info.file_size > MAX_MEMBER_BYTES:
            archive.close()
            raise FingerprintError("ZIP member exceeds size bound")
        total += info.file_size
        if total > MAX_TOTAL_UNCOMPRESSED_BYTES:
            archive.close()
            raise FingerprintError("ZIP exceeds total uncompressed size bound")
        if info.compress_size == 0:
            ratio = Decimal(0) if info.file_size == 0 else Decimal("Infinity")
        else:
            ratio = Decimal(info.file_size) / Decimal(info.compress_size)
        if ratio > MAX_COMPRESSION_RATIO:
            archive.close()
            raise FingerprintError("ZIP member exceeds compression-ratio bound")
    required = {
        "[Content_Types].xml",
        "_rels/.rels",
        "xl/workbook.xml",
        "xl/_rels/workbook.xml.rels",
        "xl/styles.xml",
        "xl/sharedStrings.xml",
    }
    if not required.issubset(set(names)):
        archive.close()
        raise FingerprintError("OOXML package is missing required parts")
    if archive.testzip() is not None:
        archive.close()
        raise FingerprintError("ZIP CRC validation failed")
    payloads: Dict[str, bytes] = {}
    manifest = []
    for info in infos:
        data = archive.read(info.filename)
        payloads[info.filename] = data
        manifest.append(
            {
                "name": info.filename,
                "uncompressed_bytes": info.file_size,
                "compressed_bytes": info.compress_size,
                "crc32": "{:08x}".format(info.CRC),
                "sha256": sha256_bytes(data),
            }
        )
    manifest_hash = sha256_bytes(canonical_json_bytes(manifest))
    return archive, payloads, manifest_hash


def _relationships(
    payloads: Mapping[str, bytes],
) -> Tuple[Dict[str, str], str]:
    manifest: List[Dict[str, str]] = []
    workbook_targets: Dict[str, str] = {}
    for name in sorted(key for key in payloads if key.endswith(".rels")):
        root = _xml_root(payloads[name], name)
        for relation in root.findall(PKG_REL + "Relationship"):
            relation_id = relation.get("Id")
            target = relation.get("Target")
            relation_type = relation.get("Type")
            mode = relation.get("TargetMode", "Internal")
            if not relation_id or not target or not relation_type:
                raise FingerprintError("relationship record is incomplete")
            if mode != "Internal":
                raise FingerprintError("external OOXML relationship is forbidden")
            manifest.append(
                {
                    "part": name,
                    "id": relation_id,
                    "target": target,
                    "type": relation_type,
                    "target_mode": mode,
                }
            )
            if name == "xl/_rels/workbook.xml.rels":
                normalized = posixpath.normpath(posixpath.join("xl", target))
                if normalized.startswith("../") or normalized.startswith("/"):
                    raise FingerprintError("workbook relationship target is unsafe")
                workbook_targets[relation_id] = normalized
    return workbook_targets, sha256_bytes(canonical_json_bytes(manifest))


def _shared_strings(data: bytes) -> Tuple[List[str], str]:
    root = _xml_root(data, "xl/sharedStrings.xml")
    values: List[str] = []
    for item in root.findall(MAIN + "si"):
        values.append("".join(node.text or "" for node in item.iter(MAIN + "t")))
    return values, sha256_bytes(canonical_json_bytes(values))


def _styles(data: bytes) -> Tuple[List[Tuple[int, str]], str]:
    root = _xml_root(data, "xl/styles.xml")
    custom: Dict[int, str] = {}
    number_formats = root.find(MAIN + "numFmts")
    if number_formats is not None:
        for item in number_formats.findall(MAIN + "numFmt"):
            number_id = item.get("numFmtId")
            code = item.get("formatCode")
            if number_id is None or code is None:
                raise FingerprintError("number format is incomplete")
            custom[int(number_id)] = code
    cell_formats = root.find(MAIN + "cellXfs")
    if cell_formats is None:
        raise FingerprintError("styles lack cellXfs")
    styles: List[Tuple[int, str]] = []
    for item in cell_formats.findall(MAIN + "xf"):
        number_id = int(item.get("numFmtId", "0"))
        styles.append((number_id, custom.get(number_id, "BUILTIN_{}".format(number_id))))
    if not styles:
        raise FingerprintError("styles contain no cell formats")
    semantic = [
        {"style_index": index, "number_format_id": value[0], "code": value[1]}
        for index, value in enumerate(styles)
    ]
    return styles, sha256_bytes(canonical_json_bytes(semantic))


def _cell_raw_value(
    cell: ET.Element,
    shared: Sequence[str],
) -> Tuple[str, str, int]:
    if cell.find(MAIN + "f") is not None:
        raise FingerprintError("worksheet formulas are forbidden")
    cell_type = cell.get("t", "n")
    style_index = int(cell.get("s", "0"))
    value_nodes = cell.findall(MAIN + "v")
    if len(value_nodes) != 1 or value_nodes[0].text is None:
        raise FingerprintError("populated worksheet cell lacks one value")
    raw = value_nodes[0].text
    if cell_type == "s":
        try:
            value = shared[int(raw)]
        except (ValueError, IndexError) as error:
            raise FingerprintError("shared-string index is invalid") from error
        return value, cell_type, style_index
    if cell_type == "n":
        parse_decimal(raw, "worksheet numeric cell")
        return raw, cell_type, style_index
    raise FingerprintError("unsupported worksheet cell type: " + cell_type)


def _vintage_axis(spec: SeriesSpec, headers: Sequence[str]) -> List[str]:
    first_index = quarter_index(spec.first_supported_vintage)
    result: List[str] = []
    pattern = re.compile(re.escape(spec.header_prefix) + r"([0-9]{2})Q([1-4])\Z")
    for offset, header in enumerate(headers):
        match = pattern.fullmatch(header)
        if match is None:
            raise FingerprintError(spec.series_id + " vintage header is malformed")
        expected_index = first_index + offset
        expected = quarter_text(expected_index)
        if int(match.group(1)) != (expected_index // 4) % 100:
            raise FingerprintError(spec.series_id + " vintage year sequence drifted")
        if int(match.group(2)) != expected_index % 4 + 1:
            raise FingerprintError(spec.series_id + " vintage quarter sequence drifted")
        result.append(expected)
    return result


def parse_panel(
    path: Path,
    spec: SeriesSpec,
    selected_pairs: Sequence[Tuple[str, str]],
) -> ParsedPanel:
    raw_bytes = _read_pinned_regular_file(path)
    if not raw_bytes.startswith(b"PK\x03\x04"):
        raise FingerprintError(spec.filename + " lacks OOXML ZIP magic")
    archive, payloads, member_hash = _safe_zip(raw_bytes)
    try:
        targets, relationship_hash = _relationships(payloads)
        workbook = _xml_root(payloads["xl/workbook.xml"], "xl/workbook.xml")
        sheets = workbook.find(MAIN + "sheets")
        if sheets is None:
            raise FingerprintError("workbook has no sheets")
        sheet_records = sheets.findall(MAIN + "sheet")
        if len(sheet_records) != 1:
            raise FingerprintError("workbook must contain exactly one sheet")
        sheet_record = sheet_records[0]
        if sheet_record.get("name") != spec.sheet_name:
            raise FingerprintError(spec.series_id + " sheet name drifted")
        relation_id = sheet_record.get(DOC_REL + "id")
        if relation_id not in targets:
            raise FingerprintError("worksheet relationship is unresolved")
        worksheet_name = targets[relation_id]
        if worksheet_name not in payloads:
            raise FingerprintError("worksheet part is absent")
        if not worksheet_name.startswith("xl/worksheets/"):
            raise FingerprintError("worksheet target is outside worksheets")
        shared, shared_hash = _shared_strings(payloads["xl/sharedStrings.xml"])
        styles, styles_hash = _styles(payloads["xl/styles.xml"])
        worksheet_bytes = payloads[worksheet_name]
        worksheet = _xml_root(worksheet_bytes, worksheet_name)
        dimension = worksheet.find(MAIN + "dimension")
        if dimension is None or dimension.get("ref") is None:
            raise FingerprintError("worksheet dimension is absent")
        dimension_text = dimension.get("ref")
        if dimension_text is None or ":" not in dimension_text:
            raise FingerprintError("worksheet dimension is malformed")
        start_ref, end_ref = dimension_text.split(":", 1)
        if start_ref != "A1":
            raise FingerprintError("worksheet dimension must begin at A1")
        max_column, max_row = split_cell_reference(end_ref)
        sheet_data = worksheet.find(MAIN + "sheetData")
        if sheet_data is None:
            raise FingerprintError("worksheet lacks sheetData")
        row_elements = sheet_data.findall(MAIN + "row")
        cells: Dict[Tuple[int, int], Tuple[str, str, int, str]] = {}
        row_numbers: List[int] = []
        trailing_empty = 0
        for row in row_elements:
            row_number_text = row.get("r")
            if row_number_text is None:
                raise FingerprintError("worksheet row lacks an index")
            row_number = int(row_number_text)
            if row_numbers and row_number <= row_numbers[-1]:
                raise FingerprintError("worksheet row order is not strict")
            row_numbers.append(row_number)
            row_cells = row.findall(MAIN + "c")
            if not row_cells:
                if row_number > max_row:
                    trailing_empty += 1
                    continue
                raise FingerprintError("empty row occurs inside declared dimension")
            if row_number > max_row:
                raise FingerprintError("nonempty row exceeds declared dimension")
            for cell in row_cells:
                reference = cell.get("r")
                if reference is None:
                    raise FingerprintError("worksheet cell lacks a reference")
                column, referenced_row = split_cell_reference(reference)
                if referenced_row != row_number or column > max_column:
                    raise FingerprintError("worksheet cell lies outside its row/dimension")
                key = (row_number, column)
                if key in cells:
                    raise FingerprintError("worksheet cell is duplicated")
                value, cell_type, style_index = _cell_raw_value(cell, shared)
                if style_index < 0 or style_index >= len(styles):
                    raise FingerprintError("worksheet style index is invalid")
                raw_node = cell.find(MAIN + "v")
                assert raw_node is not None and raw_node.text is not None
                cells[key] = (value, cell_type, style_index, raw_node.text)
        if trailing_empty > 1:
            raise FingerprintError("worksheet has excessive trailing empty rows")
        if row_numbers[:max_row] != list(range(1, max_row + 1)):
            raise FingerprintError("worksheet row axis is incomplete")
        header_values: List[str] = []
        for column in range(1, max_column + 1):
            cell = cells.get((1, column))
            if cell is None or cell[1] != "s":
                raise FingerprintError("worksheet header row is incomplete")
            header_values.append(cell[0])
        if header_values[0] != "DATE":
            raise FingerprintError("worksheet first header must be DATE")
        vintage_axis = _vintage_axis(spec, header_values[1:])
        reference_axis: List[str] = []
        for row_number in range(2, max_row + 1):
            label = cells.get((row_number, 1))
            if label is None or label[1] != "s":
                raise FingerprintError("reference-period axis is incomplete")
            reference_axis.append(canonical_reference(label[0]))
        reference_indices = [quarter_index(value) for value in reference_axis]
        if any(
            current != previous + 1
            for previous, current in zip(reference_indices, reference_indices[1:])
        ):
            raise FingerprintError("reference-period axis is not consecutive")

        grid_digest = hashlib.sha256()
        grid_digest.update(b"beforeit-us-rtdsm-semantic-grid.v1\0")
        layout_digest = hashlib.sha256()
        layout_digest.update(b"beforeit-us-rtdsm-layout.v1\0")
        numeric_count = 0
        source_missing_count = 0
        structural_count = 0
        unknown_absent_count = 0
        unsupported_count = 0
        selected: Dict[Tuple[str, str], Dict[str, Any]] = {}
        selected_set = set(selected_pairs)

        for vintage_offset, vintage in enumerate(vintage_axis, start=2):
            vintage_index = quarter_index(vintage)
            for reference_offset, reference in enumerate(reference_axis, start=2):
                key = (reference_offset, vintage_offset)
                cell = cells.get(key)
                is_structural_future = quarter_index(reference) >= vintage_index
                if cell is None:
                    if is_structural_future:
                        value_status = "STRUCTURAL_NOT_YET_OBSERVABLE"
                        structural_count += 1
                    else:
                        value_status = "UNKNOWN_ABSENT_CELL"
                        unknown_absent_count += 1
                    semantic_value = ""
                    cell_type = "ABSENT"
                    style_index = 0
                    raw_xml_value = ""
                else:
                    value, cell_type, style_index, raw_xml_value = cell
                    if cell_type == "n":
                        canonical_value = decimal_text(
                            parse_decimal(value, spec.series_id + " numeric cell")
                        )
                        value_status = "NUMERIC"
                        semantic_value = canonical_value
                        numeric_count += 1
                    elif value == "#N/A":
                        if is_structural_future:
                            value_status = "STRUCTURAL_NOT_YET_OBSERVABLE"
                            structural_count += 1
                        else:
                            value_status = "SOURCE_MISSING_MARKER"
                            source_missing_count += 1
                        semantic_value = "#N/A"
                    else:
                        unsupported_count += 1
                        raise FingerprintError(
                            spec.series_id
                            + " contains an undocumented string token: "
                            + repr(value)
                        )
                grid_digest.update(
                    (
                        vintage
                        + "\0"
                        + reference
                        + "\0"
                        + value_status
                        + "\0"
                        + semantic_value
                        + "\n"
                    ).encode("utf-8")
                )
                cell_reference = "{}{}".format(
                    excel_column_letters(vintage_offset),
                    reference_offset,
                )
                layout_digest.update(
                    (
                        cell_reference
                        + "\0"
                        + cell_type
                        + "\0"
                        + str(style_index)
                        + "\0"
                        + sha256_bytes(raw_xml_value.encode("utf-8"))
                        + "\n"
                    ).encode("utf-8")
                )
                pair = (vintage, reference)
                if pair in selected_set:
                    number_id, number_code = styles[style_index]
                    availability = (
                        "VERIFIED_AVAILABLE"
                        if value_status == "NUMERIC"
                        else (
                            "VERIFIED_UNAVAILABLE"
                            if value_status == "SOURCE_MISSING_MARKER"
                            else "UNKNOWN"
                        )
                    )
                    selected[pair] = {
                        "series_id": spec.series_id,
                        "source_sheet": spec.sheet_name,
                        "source_cell": cell_reference,
                        "source_vintage_header_text": header_values[vintage_offset - 1],
                        "canonical_vintage": vintage,
                        "source_reference_period_text": cells[(reference_offset, 1)][0],
                        "canonical_reference_period": reference,
                        "cell_type": cell_type,
                        "style_index": style_index,
                        "number_format_id": number_id,
                        "number_format_code": number_code,
                        "raw_xml_value_text": raw_xml_value,
                        "canonical_decimal_value": (
                            semantic_value if value_status == "NUMERIC" else None
                        ),
                        "value_status": value_status,
                        "availability_status": availability,
                        "evidence_grade": "CURATED_RECONSTRUCTION",
                        "strict_origin_admissible": False,
                        "gates": hard_false_gates(),
                    }
        if set(selected) != selected_set:
            raise FingerprintError(spec.series_id + " selected cells are incomplete")
        return ParsedPanel(
            spec=spec,
            raw_sha256=sha256_bytes(raw_bytes),
            raw_byte_count=len(raw_bytes),
            member_manifest_sha256=member_hash,
            relationship_manifest_sha256=relationship_hash,
            worksheet_xml_sha256=sha256_bytes(worksheet_bytes),
            shared_strings_semantic_sha256=shared_hash,
            styles_semantic_sha256=styles_hash,
            sheet_name=spec.sheet_name,
            worksheet_dimension=dimension_text,
            physical_row_element_count=len(row_elements),
            trailing_empty_row_element_count=trailing_empty,
            vintage_start=vintage_axis[0],
            vintage_end=vintage_axis[-1],
            vintage_count=len(vintage_axis),
            reference_period_start=reference_axis[0],
            reference_period_end=reference_axis[-1],
            reference_period_count=len(reference_axis),
            numeric_cell_count=numeric_count,
            source_missing_marker_count=source_missing_count,
            structural_future_cell_count=structural_count,
            unknown_absent_cell_count=unknown_absent_count,
            unknown_unsupported_token_count=unsupported_count,
            semantic_grid_sha256=grid_digest.hexdigest(),
            layout_manifest_sha256=layout_digest.hexdigest(),
            selected=selected,
        )
    finally:
        archive.close()


def _safe_raw_directory(path: Path) -> Path:
    if not path.is_absolute() or path.is_symlink():
        raise FingerprintError("raw directory is unsafe")
    resolved = path.resolve(strict=True)
    if resolved != path or not resolved.is_dir():
        raise FingerprintError("raw directory is unsafe")
    discovered = {item.name for item in resolved.iterdir() if item.suffix == ".xlsx"}
    if discovered != EXPECTED_RAW_NAMES:
        raise FingerprintError("raw directory XLSX filename set drifted")
    return resolved


def _bea_fingerprint_directory() -> Path:
    return (
        Path(__file__).resolve().parents[2]
        / "bea_nipa"
        / "historical_fingerprints"
        / "fingerprints"
    )


def _load_bea_fingerprint(digest: str) -> Dict[str, Any]:
    directory = _bea_fingerprint_directory()
    matches = list(directory.glob("*content-fingerprint-sha256-" + digest + ".json"))
    if len(matches) != 1:
        raise FingerprintError("pinned BEA fingerprint is absent or duplicated")
    path = matches[0].resolve(strict=True)
    data = path.read_bytes()
    if sha256_bytes(data) != digest:
        raise FingerprintError("pinned BEA fingerprint SHA-256 drifted")
    document = parse_json_bytes(data, "BEA fingerprint")
    if canonical_json_bytes(document) != data:
        raise FingerprintError("BEA fingerprint is not canonical JSON")
    return document


def _bea_value(document: Mapping[str, Any], target_id: str, period: str) -> Decimal:
    targets = document.get("targets")
    if not isinstance(targets, list):
        raise FingerprintError("BEA fingerprint targets are malformed")
    target = next(
        (
            value
            for value in targets
            if isinstance(value, dict) and value.get("target_id") == target_id
        ),
        None,
    )
    if not isinstance(target, dict):
        raise FingerprintError("BEA target is absent: " + target_id)
    observations = target.get("observations")
    if not isinstance(observations, list):
        raise FingerprintError("BEA target observations are malformed")
    observation = next(
        (
            value
            for value in observations
            if isinstance(value, dict) and value.get("period") == period
        ),
        None,
    )
    if not isinstance(observation, dict):
        raise FingerprintError("BEA target period is absent")
    text = observation.get("published_value_text")
    if not isinstance(text, str):
        raise FingerprintError("BEA published value is malformed")
    return parse_decimal(text, "BEA published value")


def _selected_value(panel: ParsedPanel, vintage: str, period: str) -> Decimal:
    record = panel.selected.get((vintage, period))
    if record is None or record.get("value_status") != "NUMERIC":
        raise FingerprintError("selected RTDSM value is not numeric")
    text = record.get("canonical_decimal_value")
    if not isinstance(text, str):
        raise FingerprintError("selected RTDSM decimal is malformed")
    return parse_decimal(text, "selected RTDSM value")


def crosscheck_release(
    panels: Mapping[str, ParsedPanel],
    reference_period: str,
    rtdsm_vintage: str,
    bea_fingerprint_sha256: str,
    annual_update_caveat: str,
) -> Dict[str, Any]:
    bea = _load_bea_fingerprint(bea_fingerprint_sha256)
    release = bea.get("release")
    if (
        not isinstance(release, dict)
        or release.get("annual_update_caveat") != annual_update_caveat
    ):
        raise FingerprintError("BEA annual-update caveat binding drifted")
    nominal_bea = _bea_value(bea, "nominal_gdp", reference_period)
    real_bea = _bea_value(bea, "real_gdp", reference_period)
    deflator_bea = _bea_value(bea, "gdp_deflator", reference_period)
    pce_bea = _bea_value(bea, "pce_price_index", reference_period)
    core_bea = _bea_value(bea, "core_pce_price_index", reference_period)
    nominal = _selected_value(panels["NOUTPUT"], rtdsm_vintage, reference_period)
    real = _selected_value(panels["ROUTPUT"], rtdsm_vintage, reference_period)
    price = _selected_value(panels["P"], rtdsm_vintage, reference_period)
    pcon = _selected_value(panels["PCON"], rtdsm_vintage, reference_period)
    core = _selected_value(panels["PCONX"], rtdsm_vintage, reference_period)
    with localcontext() as context:
        context.prec = 80
        nominal_scaled = (nominal_bea / Decimal(1000)).quantize(
            Decimal("0.1"),
            rounding=ROUND_HALF_UP,
        )
        real_scaled = (real_bea / Decimal(1000)).quantize(
            Decimal("0.1"),
            rounding=ROUND_HALF_UP,
        )
        lower = Decimal(100) * (nominal - Decimal("0.05")) / (
            real + Decimal("0.05")
        )
        upper = Decimal(100) * (nominal + Decimal("0.05")) / (
            real - Decimal("0.05")
        )
        if nominal_scaled != nominal or real_scaled != real:
            raise FingerprintError("RTDSM GDP scaling/rounding cross-check failed")
        if core_bea != core:
            raise FingerprintError("RTDSM core-PCE equality cross-check failed")
        if not lower <= deflator_bea <= upper:
            raise FingerprintError("implicit-deflator rounding interval failed")
        return {
            "reference_period": reference_period,
            "rtdsm_vintage": rtdsm_vintage,
            "bea_fingerprint_sha256": bea_fingerprint_sha256,
            "bea_annual_update_caveat": annual_update_caveat,
            "checks": [
                {
                    "protocol_target": "nominal_gdp",
                    "rtdsm_series_id": "NOUTPUT",
                    "result": "PASS_SOURCE_PRECISION_ROUNDING",
                    "bea_value_millions": decimal_text(nominal_bea),
                    "rtdsm_value_billions": decimal_text(nominal),
                    "comparison_value_billions_one_decimal": (
                        decimal_text(nominal_scaled)
                    ),
                    "anomaly_code": "NONE",
                },
                {
                    "protocol_target": "real_gdp",
                    "rtdsm_series_id": "ROUTPUT",
                    "result": "PASS_SOURCE_PRECISION_ROUNDING",
                    "bea_value_millions": decimal_text(real_bea),
                    "rtdsm_value_billions": decimal_text(real),
                    "comparison_value_billions_one_decimal": (
                        decimal_text(real_scaled)
                    ),
                    "anomaly_code": "NONE",
                },
                {
                    "protocol_target": "gdp_implicit_price_deflator",
                    "rtdsm_series_id": "P",
                    "result": "PASS_AUXILIARY_DERIVED_IDENTITY_ROUNDING_INTERVAL",
                    "direct_mapping_result": "NOT_COMPARABLE_KNOWN_CONCEPT_MISMATCH",
                    "bea_implicit_deflator": decimal_text(deflator_bea),
                    "rtdsm_chain_type_price_index": decimal_text(price),
                    "derived_interval_lower_closed": decimal_text(+lower),
                    "derived_interval_upper_closed": decimal_text(+upper),
                    "anomaly_code": "CONCEPT_MISMATCH",
                },
                {
                    "protocol_target": "pce_chain_type_price_index",
                    "rtdsm_series_id": "PCON",
                    "result": "NOT_COMPARABLE_KNOWN_CONCEPT_MISMATCH",
                    "bea_chain_type_price_index": decimal_text(pce_bea),
                    "rtdsm_constructed_deflator": decimal_text(pcon),
                    "diagnostic_delta_rtdsm_minus_bea": decimal_text(
                        +(pcon - pce_bea)
                    ),
                    "anomaly_code": "CONCEPT_MISMATCH",
                },
                {
                    "protocol_target": "core_pce_price_index",
                    "rtdsm_series_id": "PCONX",
                    "result": "PASS_EXACT_REPORTED_DECIMAL",
                    "bea_value": decimal_text(core_bea),
                    "rtdsm_value": decimal_text(core),
                    "anomaly_code": "NONE",
                },
            ],
            "summary": {
                "direct_comparable_target_count": 3,
                "forbidden_direct_concept_mismatch_count": 2,
                "auxiliary_derived_identity_pass_count": 1,
                "protocol_targets_supported_direct_or_derived": 4,
                "protocol_target_count": 5,
                "all_five_directly_comparable": False,
                "source_conflict_count": 0,
            },
            "gates": hard_false_gates(),
        }


def build_diagnostic(raw_dir: Path, profile_path: Path) -> Dict[str, Any]:
    profile, specs = load_profile(profile_path)
    raw = _safe_raw_directory(raw_dir)
    crosscheck_specs = _selected_crosscheck_records(profile)
    selected_pairs = [
        (
            _required_text(record, "rtdsm_vintage"),
            _required_text(record, "reference_period"),
        )
        for record in crosscheck_specs
    ]
    panels_list = [
        parse_panel(raw / spec.filename, spec, selected_pairs) for spec in specs
    ]
    panels = {panel.spec.series_id: panel for panel in panels_list}
    terminal_vintages = {panel.vintage_end for panel in panels_list}
    terminal_references = {panel.reference_period_end for panel in panels_list}
    if len(terminal_vintages) != 1 or len(terminal_references) != 1:
        raise FingerprintError("five RTDSM panels have discordant terminals")
    checks = [
        crosscheck_release(
            panels,
            _required_text(record, "reference_period"),
            _required_text(record, "rtdsm_vintage"),
            _required_text(record, "bea_fingerprint_sha256"),
            _required_text(record, "bea_annual_update_caveat"),
        )
        for record in crosscheck_specs
    ]
    if len(checks) != 2:
        raise FingerprintError("cross-check construction is incomplete")
    used = [
        {
            "used_artifact_sha256": record["bea_fingerprint_sha256"],
            "role": USED_PROVENANCE_ROLE,
            "provenance_relation": USED_PROVENANCE_RELATION,
        }
        for record in crosscheck_specs
    ]
    diagnostic = {
        "artifact": {
            "schema_version": SCHEMA_VERSION,
            "generator_version": GENERATOR_VERSION,
            "generator_sha256": sha256_file(Path(__file__).resolve()),
            "source_profile_sha256": EXPECTED_PROFILE_SHA256,
            "canonicalization": CANONICALIZATION,
            "status": STATUS,
            "evidence_class": "curated_reconstruction_research_diagnostic",
            "full_matrix_values_included": False,
            "research_use_only": True,
            "redistribution_authorized": False,
            "raw_git_commit_authorized": False,
            "model_training_authorized_by_contract": False,
            "gates": hard_false_gates(),
        },
        "classification": {
            "present_day_retrieval": True,
            "research_diagnostic": True,
            "information_set_proxy": True,
            "intraday_provenance": False,
            "historical_availability_evidence": False,
            "forecast_origin": False,
            "truth_artifact": False,
            "model_input": False,
            "score_artifact": False,
            "accuracy_evidence": False,
            "inventory_mutation": False,
            "production_use": False,
        },
        "source_attribution": profile["source_attribution"],
        "raw_bundle": {
            "hash_domain": RAW_BUNDLE_DOMAIN,
            "bundle_sha256": raw_bundle_sha256(profile, panels_list),
            "source_profile_sha256": EXPECTED_PROFILE_SHA256,
            "matrix_order": [panel.spec.series_id for panel in panels_list],
        },
        "terminal_concordance": {
            "terminal_vintage": next(iter(terminal_vintages)),
            "terminal_reference_period": next(iter(terminal_references)),
            "five_panel_terminal_concordance": True,
        },
        "panels": [panel.compact_record() for panel in panels_list],
        "selected_cells": [
            panels[series_id].selected[pair]
            for pair in selected_pairs
            for series_id in ["NOUTPUT", "ROUTPUT", "P", "PCON", "PCONX"]
        ],
        "crosschecks": checks,
        "provenance": {
            "used": used,
            "used_is_relation_not_status": True,
            "other_policy": OTHER_PROVENANCE_POLICY,
            "unknown_policy": UNKNOWN_PROVENANCE_POLICY,
        },
        "summary": {
            "panel_count": 5,
            "selected_cell_count": 10,
            "release_crosscheck_count": 2,
            "direct_comparable_target_count": 3,
            "forbidden_direct_concept_mismatch_count": 2,
            "auxiliary_derived_identity_pass_count": 1,
            "protocol_targets_supported_direct_or_derived": 4,
            "protocol_target_count": 5,
            "all_five_directly_comparable": False,
            "source_conflict_count": 0,
        },
        "gates": hard_false_gates(),
    }
    validate_compact_diagnostic(diagnostic)
    return diagnostic


def _validate_provenance(
    value: Any,
    expected_crosschecks: Sequence[Mapping[str, str]],
) -> None:
    if not isinstance(value, dict):
        raise FingerprintError("compact diagnostic provenance record is malformed")
    if set(value) != {
        "used",
        "used_is_relation_not_status",
        "other_policy",
        "unknown_policy",
    }:
        raise FingerprintError("compact diagnostic provenance keys drifted")
    if value["used_is_relation_not_status"] is not True:
        raise FingerprintError(
            "compact diagnostic used relation/status boundary drifted"
        )
    if value["other_policy"] != OTHER_PROVENANCE_POLICY:
        raise FingerprintError("compact diagnostic Other policy drifted")
    if value["unknown_policy"] != UNKNOWN_PROVENANCE_POLICY:
        raise FingerprintError("compact diagnostic unknown policy drifted")

    used = value["used"]
    if not isinstance(used, list) or len(used) != len(expected_crosschecks):
        raise FingerprintError("compact diagnostic used provenance list drifted")
    for index, (record, expected_crosscheck) in enumerate(
        zip(used, expected_crosschecks),
        start=1,
    ):
        location = f"compact diagnostic used provenance record {index}"
        if not isinstance(record, dict):
            raise FingerprintError(f"{location} is malformed")
        if set(record) != {
            "used_artifact_sha256",
            "role",
            "provenance_relation",
        }:
            raise FingerprintError(f"{location} keys drifted")
        expected_hash = expected_crosscheck["bea_fingerprint_sha256"]
        artifact_hash = record["used_artifact_sha256"]
        if (
            not isinstance(artifact_hash, str)
            or HASH_RE.fullmatch(artifact_hash) is None
        ):
            raise FingerprintError(f"{location} artifact hash is malformed")
        if artifact_hash != expected_hash:
            raise FingerprintError(f"{location} artifact binding drifted")
        if record["role"] != USED_PROVENANCE_ROLE:
            raise FingerprintError(f"{location} role drifted")
        if record["provenance_relation"] != USED_PROVENANCE_RELATION:
            raise FingerprintError(f"{location} relation drifted")


def validate_compact_diagnostic(document: Mapping[str, Any]) -> None:
    expected_top = {
        "artifact",
        "classification",
        "source_attribution",
        "raw_bundle",
        "terminal_concordance",
        "panels",
        "selected_cells",
        "crosschecks",
        "provenance",
        "summary",
        "gates",
    }
    if set(document) != expected_top:
        raise FingerprintError("compact diagnostic top-level structure drifted")
    artifact = document.get("artifact")
    if not isinstance(artifact, dict):
        raise FingerprintError("compact diagnostic artifact record is malformed")
    if artifact.get("schema_version") != SCHEMA_VERSION:
        raise FingerprintError("compact diagnostic schema drifted")
    if artifact.get("source_profile_sha256") != EXPECTED_PROFILE_SHA256:
        raise FingerprintError("compact diagnostic profile binding drifted")
    if artifact.get("full_matrix_values_included") is not False:
        raise FingerprintError("compact diagnostic cannot include full matrices")
    raw_bundle = document.get("raw_bundle")
    if (
        not isinstance(raw_bundle, dict)
        or raw_bundle.get("hash_domain") != RAW_BUNDLE_DOMAIN
        or raw_bundle.get("source_profile_sha256") != EXPECTED_PROFILE_SHA256
        or raw_bundle.get("matrix_order")
        != ["NOUTPUT", "ROUTPUT", "P", "PCON", "PCONX"]
        or not isinstance(raw_bundle.get("bundle_sha256"), str)
        or HASH_RE.fullmatch(str(raw_bundle.get("bundle_sha256"))) is None
    ):
        raise FingerprintError("compact diagnostic raw-bundle binding drifted")
    for record in (artifact.get("gates"), document.get("gates")):
        if record != hard_false_gates():
            raise FingerprintError("compact diagnostic hard-false gates drifted")
    summary = document.get("summary")
    expected_summary = {
        "panel_count": 5,
        "selected_cell_count": 10,
        "release_crosscheck_count": 2,
        "direct_comparable_target_count": 3,
        "forbidden_direct_concept_mismatch_count": 2,
        "auxiliary_derived_identity_pass_count": 1,
        "protocol_targets_supported_direct_or_derived": 4,
        "protocol_target_count": 5,
        "all_five_directly_comparable": False,
        "source_conflict_count": 0,
    }
    if summary != expected_summary:
        raise FingerprintError("compact diagnostic summary drifted")
    terminal = document.get("terminal_concordance")
    if (
        not isinstance(terminal, dict)
        or terminal.get("five_panel_terminal_concordance") is not True
    ):
        raise FingerprintError("compact diagnostic terminal record drifted")
    panels = document.get("panels")
    if not isinstance(panels, list) or len(panels) != 5:
        raise FingerprintError("compact diagnostic panel count drifted")
    expected_ids = ["NOUTPUT", "ROUTPUT", "P", "PCON", "PCONX"]
    if [panel.get("series_id") for panel in panels if isinstance(panel, dict)] != (
        expected_ids
    ):
        raise FingerprintError("compact diagnostic panel order drifted")
    for panel in panels:
        if not isinstance(panel, dict):
            raise FingerprintError("compact diagnostic panel is malformed")
        for key in (
            "raw_sha256",
            "zip_member_manifest_sha256",
            "workbook_relationship_manifest_sha256",
            "worksheet_xml_sha256",
            "shared_strings_semantic_sha256",
            "styles_semantic_sha256",
            "semantic_grid_sha256",
            "layout_manifest_sha256",
        ):
            value = panel.get(key)
            if not isinstance(value, str) or HASH_RE.fullmatch(value) is None:
                raise FingerprintError("compact diagnostic hash is malformed")
        if panel.get("unknown_absent_cell_count") != 0:
            raise FingerprintError("official panel contains an unknown absent cell")
        if panel.get("unknown_unsupported_token_count") != 0:
            raise FingerprintError("official panel contains an unsupported token")
        if panel.get("gates") != hard_false_gates():
            raise FingerprintError("compact panel gates drifted")
    selected = document.get("selected_cells")
    if not isinstance(selected, list) or len(selected) != 10:
        raise FingerprintError("selected-cell count drifted")
    for cell in selected:
        if not isinstance(cell, dict) or cell.get("value_status") != "NUMERIC":
            raise FingerprintError("selected diagnostic cell is not numeric")
        if cell.get("evidence_grade") != "CURATED_RECONSTRUCTION":
            raise FingerprintError("selected diagnostic evidence grade drifted")
        if cell.get("strict_origin_admissible") is not False:
            raise FingerprintError("selected diagnostic cell became admissible")
        if cell.get("gates") != hard_false_gates():
            raise FingerprintError("selected diagnostic cell gates drifted")
    checks = document.get("crosschecks")
    if not isinstance(checks, list) or len(checks) != 2:
        raise FingerprintError("cross-check count drifted")
    pinned_profile, _ = load_profile(default_profile_path())
    expected_crosschecks = _selected_crosscheck_records(pinned_profile)
    expected_by_period = {
        record["reference_period"]: record for record in expected_crosschecks
    }
    for record, expected_period in zip(
        checks,
        EXPECTED_CROSSCHECK_REFERENCE_PERIODS,
    ):
        if not isinstance(record, dict):
            raise FingerprintError("cross-check record is malformed")
        if record.get("reference_period") != expected_period:
            raise FingerprintError("cross-check period order drifted")
        expected_identity = expected_by_period[expected_period]
        for key in (
            "rtdsm_vintage",
            "bea_fingerprint_sha256",
            "bea_annual_update_caveat",
        ):
            if record.get(key) != expected_identity[key]:
                raise FingerprintError(
                    f"cross-check {expected_period} {key} binding drifted"
                )
        if record.get("summary") != {
            "direct_comparable_target_count": 3,
            "forbidden_direct_concept_mismatch_count": 2,
            "auxiliary_derived_identity_pass_count": 1,
            "protocol_targets_supported_direct_or_derived": 4,
            "protocol_target_count": 5,
            "all_five_directly_comparable": False,
            "source_conflict_count": 0,
        }:
            raise FingerprintError("cross-check summary drifted")
        rows = record.get("checks")
        if not isinstance(rows, list) or len(rows) != 5:
            raise FingerprintError("cross-check target rows drifted")
        by_target = {
            row.get("protocol_target"): row
            for row in rows
            if isinstance(row, dict)
        }
        if set(by_target) != {
            "nominal_gdp",
            "real_gdp",
            "gdp_implicit_price_deflator",
            "pce_chain_type_price_index",
            "core_pce_price_index",
        }:
            raise FingerprintError("cross-check target identities drifted")
        if by_target["nominal_gdp"].get("result") != (
            "PASS_SOURCE_PRECISION_ROUNDING"
        ):
            raise FingerprintError("nominal-GDP cross-check drifted")
        if by_target["real_gdp"].get("result") != (
            "PASS_SOURCE_PRECISION_ROUNDING"
        ):
            raise FingerprintError("real-GDP cross-check drifted")
        deflator = by_target["gdp_implicit_price_deflator"]
        if (
            deflator.get("anomaly_code") != "CONCEPT_MISMATCH"
            or deflator.get("direct_mapping_result")
            != "NOT_COMPARABLE_KNOWN_CONCEPT_MISMATCH"
        ):
            raise FingerprintError("GDP-price concept mismatch was lost")
        lower = parse_decimal(
            str(deflator.get("derived_interval_lower_closed")),
            "derived deflator lower interval",
        )
        upper = parse_decimal(
            str(deflator.get("derived_interval_upper_closed")),
            "derived deflator upper interval",
        )
        bea_value = parse_decimal(
            str(deflator.get("bea_implicit_deflator")),
            "BEA implicit deflator",
        )
        if not lower <= bea_value <= upper:
            raise FingerprintError("derived deflator interval no longer contains BEA")
        pce = by_target["pce_chain_type_price_index"]
        if (
            pce.get("anomaly_code") != "CONCEPT_MISMATCH"
            or pce.get("result") != "NOT_COMPARABLE_KNOWN_CONCEPT_MISMATCH"
        ):
            raise FingerprintError("PCE-price concept mismatch was lost")
        if by_target["core_pce_price_index"].get("result") != (
            "PASS_EXACT_REPORTED_DECIMAL"
        ):
            raise FingerprintError("core-PCE cross-check drifted")
        if record.get("gates") != hard_false_gates():
            raise FingerprintError("cross-check gates drifted")
    _validate_provenance(
        document.get("provenance"),
        expected_crosschecks,
    )


def _safe_output_directory(path: Path) -> Path:
    if not path.is_absolute() or path.is_symlink():
        raise FingerprintError("output directory is unsafe")
    if path.exists():
        resolved = path.resolve(strict=True)
        if resolved != path or not resolved.is_dir():
            raise FingerprintError("output directory is unsafe")
        return resolved
    parent = path.parent.resolve(strict=True)
    if not parent.is_dir() or parent.is_symlink():
        raise FingerprintError("output parent is unsafe")
    path.mkdir(mode=0o755)
    return path.resolve(strict=True)


def _existing_matches(path: Path, data: bytes) -> bool:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except FileNotFoundError:
        return False
    except OSError as error:
        raise FingerprintError("existing artifact is unsafe") from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise FingerprintError("existing artifact is unsafe")
        chunks: List[bytes] = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        path_metadata = os.stat(path, follow_symlinks=False)
        if (
            not stat.S_ISREG(path_metadata.st_mode)
            or path_metadata.st_nlink != 1
            or (path_metadata.st_dev, path_metadata.st_ino)
            != (metadata.st_dev, metadata.st_ino)
        ):
            raise FingerprintError("existing artifact changed during validation")
        if b"".join(chunks) != data:
            raise FingerprintError("content-addressed artifact bytes differ")
        return True
    finally:
        os.close(descriptor)


def write_content_addressed(output_dir: Path, data: bytes) -> Path:
    output = _safe_output_directory(output_dir)
    digest = sha256_bytes(data)
    destination = output / (
        "rtdsm-quarterly-research-diagnostic-sha256-" + digest + ".json"
    )
    if _existing_matches(destination, data):
        return destination
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output,
        prefix=".rtdsm-fingerprint-",
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        remaining = memoryview(data)
        while remaining:
            written = os.write(descriptor, remaining)
            if written <= 0:
                raise FingerprintError("temporary artifact write made no progress")
            remaining = remaining[written:]
        os.fsync(descriptor)
        pinned = os.fstat(descriptor)
        path_metadata = os.stat(temporary, follow_symlinks=False)
        if (
            not stat.S_ISREG(pinned.st_mode)
            or pinned.st_nlink != 1
            or (pinned.st_dev, pinned.st_ino)
            != (path_metadata.st_dev, path_metadata.st_ino)
        ):
            raise FingerprintError("temporary artifact is unsafe")
        try:
            os.link(temporary, destination, follow_symlinks=False)
        except FileExistsError:
            if not _existing_matches(destination, data):
                raise FingerprintError("exclusive artifact publication lost a race")
            return destination
        linked = os.stat(destination, follow_symlinks=False)
        pinned = os.fstat(descriptor)
        if (
            not stat.S_ISREG(linked.st_mode)
            or (linked.st_dev, linked.st_ino) != (pinned.st_dev, pinned.st_ino)
            or pinned.st_nlink != 2
        ):
            raise FingerprintError("temporary artifact source changed")
        os.lseek(descriptor, 0, os.SEEK_SET)
        chunks: List[bytes] = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        if b"".join(chunks) != data:
            raise FingerprintError("temporary artifact bytes changed")
        os.fchmod(descriptor, 0o644)
        os.fsync(descriptor)
    finally:
        try:
            pinned = os.fstat(descriptor)
            current = os.stat(temporary, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            if (current.st_dev, current.st_ino) == (pinned.st_dev, pinned.st_ino):
                temporary.unlink()
        os.close(descriptor)
    if not _existing_matches(destination, data):
        raise FingerprintError("published artifact is absent")
    return destination


def default_profile_path() -> Path:
    return Path(__file__).resolve().parent.parent / "rtdsm_quarterly_profile.json"


def default_output_dir() -> Path:
    return Path(__file__).resolve().parent / "artifacts"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, required=True)
    parser.add_argument("--profile", type=Path, default=default_profile_path())
    parser.add_argument("--output-dir", type=Path, default=default_output_dir())
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    raw_dir = arguments.raw_dir
    profile = arguments.profile
    output = arguments.output_dir
    if not raw_dir.is_absolute():
        raw_dir = raw_dir.resolve()
    if not profile.is_absolute():
        profile = profile.resolve()
    if not output.is_absolute():
        output = output.resolve()
    diagnostic = build_diagnostic(raw_dir, profile)
    data = canonical_json_bytes(diagnostic)
    path = write_content_addressed(output, data)
    print(path)
    print("sha256=" + sha256_bytes(data))
    print("panels=5")
    print("selected_cells=10")
    print("direct_comparable_targets=3")
    print("forbidden_direct_concept_mismatches=2")
    print("auxiliary_derived_identity_passes=1")
    print("status=" + STATUS)
    for gate, value in hard_false_gates().items():
        print("{}={}".format(gate, str(value).lower()))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FingerprintError as error:
        print("error: " + str(error), file=sys.stderr)
        raise SystemExit(1) from error
