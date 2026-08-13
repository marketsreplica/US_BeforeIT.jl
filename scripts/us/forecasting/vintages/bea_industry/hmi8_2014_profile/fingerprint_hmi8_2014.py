#!/usr/bin/env python3
"""Fail-closed profile for the present-day BEA HMI8 January-2014 archive.

The accepted inputs are four discovery responses, two outer ZIP archives, and
four OOXML members extracted byte-for-byte from ``AllTablesIO.zip``.  The
result is structural/accounting evidence only.  It is deliberately incapable
of emitting an ABM state, admitting a forecast origin, or allocating the
historically combined real-estate and federal-government sectors.
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
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping, Sequence


MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
OFFICE_REL_NS = (
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
)
PACKAGE_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
CONTENT_TYPE_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
CORE_NS = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
DC_NS = "http://purl.org/dc/elements/1.1/"
DCTERMS_NS = "http://purl.org/dc/terms/"
XML_NS = "http://www.w3.org/XML/1998/namespace"
REL_ID = "{%s}id" % OFFICE_REL_NS
M = "{%s}" % MAIN_NS
P = "{%s}" % PACKAGE_REL_NS
CT = "{%s}" % CONTENT_TYPE_NS

SCHEMA_VERSION = "beforeit-us-bea-hmi8-2014-archive-profile.v1"
PARSER_VERSION = "beforeit-us-bea-hmi8-2014-ooxml-parser.v1"
PROFILE_ID = "bea_hmi8_january_2014_present_day_archive.v1"
STATUS = "PRESENT_DAY_ARCHIVE_RETRIEVAL_NONADMITTING_PROFILE_CANDIDATE"
DIRECTORY = "2012/GDP_by_Industry/Annual/Comprehensive_January-23-2014"
DIRECTORY_ID = "12290"
RELEASE_DATE = "2014-01-23"
RELEASE_AVAILABILITY_CEILING = "2014-01-23T23:59:59.999999-05:00"
PRESENT_DAY_CAPTURE_TIMESTAMP_UTC = "2026-08-08T00:33:13Z"
CANONICALIZATION = "utf8_sorted_keys_compact_json_lf"

HASH_RE = re.compile(r"[0-9a-f]{64}\Z", re.ASCII)
UINT_RE = re.compile(r"(?:0|[1-9][0-9]*)\Z", re.ASCII)
INT_RE = re.compile(r"(?:0|-?[1-9][0-9]*)\Z", re.ASCII)
CELL_RE = re.compile(r"([A-Z]+)([1-9][0-9]*)\Z", re.ASCII)
REL_ID_RE = re.compile(r"rId[1-9][0-9]*\Z", re.ASCII)
CODE_RE = re.compile(r"[A-Za-z0-9]+\Z", re.ASCII)
YEAR_SHEETS = tuple(str(year) for year in range(1997, 2013))

MAX_ZIP_MEMBERS = 512
MAX_ZIP_MEMBER_BYTES = 64_000_000
MAX_ZIP_TOTAL_BYTES = 192_000_000

WORKSHEET_REL = OFFICE_REL_NS + "/worksheet"
HYPERLINK_REL = OFFICE_REL_NS + "/hyperlink"
ALLOWED_REL_TYPES = {
    OFFICE_REL_NS + "/extended-properties",
    OFFICE_REL_NS + "/officeDocument",
    OFFICE_REL_NS + "/custom-properties",
    OFFICE_REL_NS + "/worksheet",
    OFFICE_REL_NS + "/sharedStrings",
    OFFICE_REL_NS + "/styles",
    OFFICE_REL_NS + "/theme",
    OFFICE_REL_NS + "/printerSettings",
    OFFICE_REL_NS + "/hyperlink",
    OFFICE_REL_NS + "/calcChain",
    PACKAGE_REL_NS + "/metadata/core-properties",
}

SUMMARY_CODES = (
    "111CA",
    "113FF",
    "211",
    "212",
    "213",
    "22",
    "23",
    "321",
    "327",
    "331",
    "332",
    "333",
    "334",
    "335",
    "3361MV",
    "3364OT",
    "337",
    "339",
    "311FT",
    "313TT",
    "315AL",
    "322",
    "323",
    "324",
    "325",
    "326",
    "42",
    "441",
    "445",
    "452",
    "4A0",
    "481",
    "482",
    "483",
    "484",
    "485",
    "486",
    "487OS",
    "493",
    "511",
    "512",
    "513",
    "514",
    "521CI",
    "523",
    "524",
    "525",
    "531",
    "532RL",
    "5411",
    "5415",
    "5412OP",
    "55",
    "561",
    "562",
    "61",
    "621",
    "622",
    "623",
    "624",
    "711AS",
    "713",
    "721",
    "722",
    "81",
    "GFG",
    "GFE",
    "GSLG",
    "GSLE",
)
SUMMARY_FINAL_USE_CODES = (
    "F010",
    "F020",
    "F030",
    "F040",
    "F050",
    "F06C",
    "F06I",
    "F07C",
    "F07I",
    "F10C",
    "F10I",
)
DETAIL_SPECIAL_CODES = ("S00401", "S00402", "S00300", "S00900")

OUTER_IO_MEMBERS = (
    "IOMake_Before_Redefinitions_2007_Detail.xlsx",
    "IOUse_After_Redefinitions_PRO_1997-2012_Sector.xlsx",
    "IOUse_After_Redefinitions_PRO_1997-2012_Summary.xlsx",
    "IOUse_After_Redefinitions_PRO_2007_Detail.xlsx",
    "IOUse_After_Redefinitions_PUR_2007_Detail.xlsx",
    "IOUse_After_Redefinitions_PUR_2007_Sector.xlsx",
    "IOUse_After_Redefinitions_PUR_2007_Summary.xlsx",
    "IOUse_Before_Redefinitions_PRO_1997-2012_Sector.xlsx",
    "IOUse_Before_Redefinitions_PRO_1997-2012_Summary.xlsx",
    "IOUse_Before_Redefinitions_PRO_2007_Detail.xlsx",
    "IOUse_Before_Redefinitions_PUR_2007_Detail.xlsx",
    "IOUse_Before_Redefinitions_PUR_2007_Sector.xlsx",
    "IOUse_Before_Redefinitions_PUR_2007_Summary.xlsx",
    "IxC_TR_1997-2012_Sector.xlsx",
    "IxC_TR_1997-2012_Summary.xlsx",
    "IxC_TR_2007_Detail.xlsx",
    "IxI_TR_1997-2012_Sector.xlsx",
    "IxI_TR_1997-2012_Summary.xlsx",
    "IxI_TR_2007_Detail.xlsx",
    "CxC_TR_1997-2012_Sector.xlsx",
    "CxC_TR_1997-2012_Summary.xlsx",
    "CxC_TR_2007_Detail.xlsx",
    "CxI_DR_1997-2012_Sector.xlsx",
    "CxI_DR_1997-2012_Summary.xlsx",
    "CxI_DR_2007_detail.xlsx",
    "IOMake_After_Redefinitions_1997-2012_Sector.xlsx",
    "IOMake_After_Redefinitions_1997-2012_Summary.xlsx",
    "IOMake_After_Redefinitions_2007_Detail.xlsx",
    "IOMake_Before_Redefinitions_1997-2012_Sector.xlsx",
    "IOMake_Before_Redefinitions_1997-2012_Summary.xlsx",
)
OUTER_LEGACY_MEMBERS = (
    "ValueAdded.xls",
    "Employment.xls",
    "GrossOutput.xls",
    "IntermediateInputs.xls",
    "KLEMS.xls",
)

EXTERNAL_HYPERLINKS = {
    "http://www.bea.gov/papers/pdf/IOmanual_092906.pdf",
    (
        "http://www.bea.gov/scb/pdf/2013/06%20June/"
        "0613_preview_comprehensive_iea_revision.pdf"
    ),
    "mailto:industryeconomicaccounts@bea.gov",
    "http://www.bea.gov/scb/pdf/2004/03March/0304IndustryAcctsV3.pdf",
}

SUMMARY_MAKE_README = (
    "This file contains summary-level Make table after redefinitions data from "
    "the Industry Input-Output (I-O) accounts for the years 1997-2012. These "
    "data were released on January 23, 2014, as part of the comprehensive "
    "revision to the industry economic accounts (IEAs). Statistics were "
    "prepared with methodologies that are unique to the I-O accounts and are "
    "for industries defined according to the 2007 North American Industry "
    "Classification System (NAICS). The \"NAICS codes\" tab contains a "
    "concordance of the I-O codes to the associated 2007 NAICS codes."
)
SUMMARY_USE_README = SUMMARY_MAKE_README.replace("Make table", "Use table")
DETAIL_POST_RELEASE_NOTE = (
    "Note: On February 14, 2014, the level of detail was aggregated for the "
    "real estate industry in the benchmark detail-publication level products "
    "(388 industries).  In the future, this sector will be expanded to include "
    "a breakout of residential real estate separate from nonresidential real "
    "estate.  "
)


class ProfileError(RuntimeError):
    """Raised when any closed-profile invariant fails."""


@dataclass(frozen=True)
class FileSpec:
    name: str
    byte_count: int
    sha256: str


@dataclass(frozen=True)
class WorkbookSpec:
    key: str
    filename: str
    byte_count: int
    sha256: str
    kind: str
    sheets: tuple[str, ...]
    dimensions: tuple[str, ...]
    core_properties: tuple[tuple[str, str], ...]
    readme_cell: str
    readme_text: str
    expected_structure_sha256: str


CAPTURE_SPECS = (
    FileSpec(
        "hmi8-root.json",
        40_651,
        "3ec9431c62fa419595f6acbe485c683adb1ebba67924862f5677271eb8d51a1e",
    ),
    FileSpec(
        "url-path-id.json",
        70,
        "6156a2acaa650ed89472b50604ded7ac8540bc1a34809887edf6dde833751d9a",
    ),
    FileSpec(
        "get-path.json",
        192,
        "9e32cb466447d4f8492131acfbbe6b61ef8df154d9160bde171e97fc84b6230c",
    ),
    FileSpec(
        "release-files.json",
        4_203,
        "ac2bdf3c8ee61473d45f3880158b00a30d38ec67cca42d6f4ee1c53853beafa7",
    ),
    FileSpec(
        "AllTablesIO.zip",
        15_397_981,
        "c98eff9b134e66429d12a740d72306e08de3bd29703aa6ea56310262a7879330",
    ),
    FileSpec(
        "AllTables.zip",
        537_569,
        "08209ee802eec3773a49f7cac7a0b82e6b0f86bf6176028b2a19ff4d27f0a409",
    ),
)

WORKBOOK_SPECS = (
    WorkbookSpec(
        "summary_make",
        "IOMake_After_Redefinitions_1997-2012_Summary.xlsx",
        618_395,
        "67735472f7ed832df3603fbf234b7a8404e4fe8e70884c3f112426e32637e750",
        "summary_make",
        ("ReadMe", "NAICS codes") + YEAR_SHEETS,
        ("A1:A29", "A1:I721") + ("A2:BV222",) * 16,
        (
            ("creator", "U.S. Department of Commerce"),
            ("lastModifiedBy", "Howells, Thomas"),
            ("lastPrinted", "2008-01-24T15:01:09Z"),
            ("created", "2004-06-14T13:11:21Z"),
            ("modified", "2014-01-18T21:53:14Z"),
        ),
        "A3",
        SUMMARY_MAKE_README,
        "8bc6bc60552f512c3fc9cbfcbc5a4c60b057a5f03671f695745858f7d22408ed",
    ),
    WorkbookSpec(
        "summary_use",
        "IOUse_After_Redefinitions_PRO_1997-2012_Summary.xlsx",
        767_039,
        "3313ccd997d995d2f9354148587d1358e914d30ca6cad550ed2a45842696af62",
        "summary_use",
        ("ReadMe", "NAICS codes") + YEAR_SHEETS,
        ("A1:IV29", "A1:I721") + ("A1:CG86",) * 16,
        (
            ("creator", "U.S. Department of Commerce"),
            ("lastModifiedBy", "Howells, Thomas"),
            ("lastPrinted", "2010-05-19T19:05:49Z"),
            ("created", "2004-06-14T13:11:21Z"),
            ("modified", "2014-01-18T22:06:27Z"),
        ),
        "A3",
        SUMMARY_USE_README,
        "8e1d6d5dd6ba78db249e9ce31118a1aa5524ba7f7c5f04fb2ee3fb7661cd8229",
    ),
    WorkbookSpec(
        "detail_make",
        "IOMake_After_Redefinitions_2007_Detail.xlsx",
        499_255,
        "b3cf4d96ab651c3d9c6f4a1f1e340cc77e40a2995a060a5588393b092a7c7669",
        "detail_make",
        ("ReadMe", "NAICS codes", "2007"),
        ("A1:A28", "A1:I721", "A2:OA400"),
        (
            ("creator", "Administrator"),
            ("lastModifiedBy", "Howells, Thomas"),
            ("created", "2013-12-04T15:42:04Z"),
            ("modified", "2014-02-14T17:39:58Z"),
        ),
        "A3",
        DETAIL_POST_RELEASE_NOTE,
        "e3210bc9aa2c19adf8dbe23085f6c512b97fe23dbd1d6c79b6499a71d7a0bf6d",
    ),
    WorkbookSpec(
        "detail_use",
        "IOUse_After_Redefinitions_PRO_2007_Detail.xlsx",
        728_138,
        "52f5b354a9647ef01fc68f3c1c82a7cb194f03f55ec6a16ace48752ae34f49e5",
        "detail_use",
        ("ReadMe", "NAICS codes", "2007"),
        ("A1:IV28", "A1:I721", "A1:OP405"),
        (
            ("creator", "Lyndaker, Amanda"),
            ("lastModifiedBy", "Howells, Thomas"),
            ("created", "2013-12-04T16:02:13Z"),
            ("modified", "2014-02-14T17:39:46Z"),
        ),
        "A3",
        DETAIL_POST_RELEASE_NOTE,
        "3843b0356c918bf9a42cdd95878026569f66ffb349326116aa14a0adc2553183",
    ),
)

EXPECTED_PROFILE_CONTRACT_SHA256 = (
    "8d2555d0b2bd449253c27bf3da562b4dbe2011a3c64f1689f560471c69f5c8df"
)
EXPECTED_ARTIFACT_SHA256 = (
    "79e96950772bbd172f26ef7a53f096862cd0d87f0cc4de1f244fd336d164508a"
)


@dataclass(frozen=True)
class Cell:
    reference: str
    row: int
    column: int
    cell_type: str | None
    style_index: int
    value: str | None
    formula: str | None


@dataclass
class WorkbookView:
    spec: WorkbookSpec
    shared_strings: list[str]
    num_formats: list[int]
    sheets: dict[str, dict[str, Cell]]
    sheet_parts: dict[str, str]
    structure: dict[str, Any]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            allow_nan=False,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")


def canonical_sha256(value: Any) -> str:
    return sha256_bytes(canonical_json_bytes(value))


def false_gates() -> dict[str, bool]:
    return {
        "contemporaneous_bytes_observed": False,
        "exact_historical_bytes_independently_proven": False,
        "historical_first_state_verified": False,
        "historical_availability_verified": False,
        "intraday_availability_verified": False,
        "origin_admissible": False,
        "target_admissible": False,
        "abm_state_emitted": False,
        "later_share_allocation_allowed": False,
        "model_input_allowed": False,
        "forecast_execution_allowed": False,
        "score_allowed": False,
        "accuracy_evidence": False,
        "promotion_eligible": False,
        "inventory_mutation_authorized": False,
        "production_authorized": False,
        "ready": False,
    }


def profile_contract_payload() -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "parser_version": PARSER_VERSION,
        "profile_id": PROFILE_ID,
        "directory": DIRECTORY,
        "directory_id": DIRECTORY_ID,
        "capture_specs": [asdict(item) for item in CAPTURE_SPECS],
        "workbook_specs": [asdict(item) for item in WORKBOOK_SPECS],
        "ordinary_summary_axis": list(SUMMARY_CODES),
        "detail_special_codes": list(DETAIL_SPECIAL_CODES),
        "formula_policy": "only exact 2007!OP337:OP344 orphan errors",
        "integer_grammar": INT_RE.pattern,
        "gates": false_gates(),
    }


def profile_contract_sha256() -> str:
    return canonical_sha256(profile_contract_payload())


def _validate_contract() -> None:
    for item in (*CAPTURE_SPECS, *WORKBOOK_SPECS):
        if HASH_RE.fullmatch(item.sha256) is None:
            raise ProfileError("profile contains an invalid SHA-256")
    if len(SUMMARY_CODES) != 69 or len(set(SUMMARY_CODES)) != 69:
        raise ProfileError("summary ordinary axis is not exactly 69 unique codes")
    if any(not item.expected_structure_sha256 for item in WORKBOOK_SPECS):
        raise ProfileError("workbook structure hashes have not been frozen")
    if profile_contract_sha256() != EXPECTED_PROFILE_CONTRACT_SHA256:
        raise ProfileError("profile contract SHA-256 drifted")


def _json_no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ProfileError("JSON contains duplicate object member %r" % key)
        result[key] = value
    return result


def parse_json(data: bytes, location: str) -> Any:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ProfileError("%s is not UTF-8" % location) from error
    try:
        return json.loads(text, object_pairs_hook=_json_no_duplicates)
    except (json.JSONDecodeError, ValueError) as error:
        raise ProfileError("%s is not closed-profile JSON" % location) from error


def _read_regular_file(path: Path, spec: FileSpec | WorkbookSpec) -> bytes:
    try:
        before = path.stat(follow_symlinks=False)
    except OSError as error:
        raise ProfileError("cannot stat %s" % path) from error
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
        raise ProfileError("input is not a direct regular file: %s" % path)
    if before.st_nlink != 1:
        raise ProfileError("hard-linked input is forbidden: %s" % path)
    try:
        data = path.read_bytes()
        after = path.stat(follow_symlinks=False)
    except OSError as error:
        raise ProfileError("cannot read %s" % path) from error
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
    if identity_before != identity_after:
        raise ProfileError("input changed during read: %s" % path)
    if len(data) != spec.byte_count or sha256_bytes(data) != spec.sha256:
        raise ProfileError("pinned identity mismatch: %s" % path)
    return data


def _parse_xml(data: bytes, location: str) -> ET.Element:
    prefix = data[:8192].upper()
    if b"<!DOCTYPE" in prefix or b"<!ENTITY" in prefix:
        raise ProfileError("%s contains a forbidden XML declaration" % location)
    try:
        return ET.fromstring(data)
    except ET.ParseError as error:
        raise ProfileError("%s is malformed XML" % location) from error


def _uint(token: str, location: str) -> int:
    if UINT_RE.fullmatch(token) is None:
        raise ProfileError("%s is not a canonical unsigned integer" % location)
    return int(token)


def column_number(name: str) -> int:
    if re.fullmatch(r"[A-Z]+", name, re.ASCII) is None:
        raise ProfileError("invalid Excel column %r" % name)
    value = 0
    for character in name:
        value = value * 26 + ord(character) - 64
    return value


def column_name(number: int) -> str:
    if number < 1:
        raise ProfileError("Excel column number must be positive")
    result = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        result = chr(65 + remainder) + result
    return result


def _cell_coordinates(reference: str) -> tuple[int, int]:
    match = CELL_RE.fullmatch(reference)
    if match is None:
        raise ProfileError("invalid cell reference %r" % reference)
    column = column_number(match.group(1))
    row = int(match.group(2))
    if column > 16_384 or row > 1_048_576:
        raise ProfileError("cell reference exceeds OOXML worksheet bounds")
    return row, column


def _safe_member_name(name: str) -> str:
    if not name or "\x00" in name or "\\" in name or name.endswith("/"):
        raise ProfileError("unsafe ZIP member name")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise ProfileError("unsafe ZIP member path %r" % name)
    if str(path) != name:
        raise ProfileError("noncanonical ZIP member path %r" % name)
    return name


def validate_zip_bytes(
    data: bytes, location: str, expected_names: Sequence[str] | None = None
) -> tuple[dict[str, bytes], dict[str, Any]]:
    if not data.startswith(b"PK"):
        raise ProfileError("%s lacks a ZIP signature" % location)
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as error:
        raise ProfileError("%s is not a valid ZIP" % location) from error
    infos = archive.infolist()
    if not infos or len(infos) > MAX_ZIP_MEMBERS:
        raise ProfileError("%s has an invalid member count" % location)
    names: set[str] = set()
    folded: set[str] = set()
    total = 0
    records: list[dict[str, Any]] = []
    members: dict[str, bytes] = {}
    for position, info in enumerate(infos, start=1):
        name = _safe_member_name(info.filename)
        if name in names or name.casefold() in folded:
            raise ProfileError("duplicate or case-aliased ZIP member %s" % name)
        names.add(name)
        folded.add(name.casefold())
        if info.flag_bits & 1:
            raise ProfileError("encrypted ZIP member is forbidden")
        if info.compress_type not in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED}:
            raise ProfileError("unsupported ZIP compression method")
        mode = (info.external_attr >> 16) & 0xFFFF
        if stat.S_IFMT(mode) == stat.S_IFLNK:
            raise ProfileError("ZIP symbolic links are forbidden")
        if info.file_size < 0 or info.file_size > MAX_ZIP_MEMBER_BYTES:
            raise ProfileError("ZIP member size is outside the profile limit")
        total += info.file_size
        if total > MAX_ZIP_TOTAL_BYTES:
            raise ProfileError("ZIP total uncompressed size exceeds the limit")
        try:
            payload = archive.read(info)
        except (zipfile.BadZipFile, RuntimeError) as error:
            raise ProfileError("ZIP CRC/decompression failure for %s" % name) from error
        if len(payload) != info.file_size:
            raise ProfileError("ZIP member size mismatch for %s" % name)
        members[name] = payload
        records.append(
            {
                "position": position,
                "name": name,
                "crc32": "%08x" % info.CRC,
                "byte_count": info.file_size,
                "compressed_byte_count": info.compress_size,
                "compression": info.compress_type,
                "flag_bits": info.flag_bits,
                "content_sha256": sha256_bytes(payload),
            }
        )
    archive.close()
    if expected_names is not None and tuple(item["name"] for item in records) != tuple(
        expected_names
    ):
        raise ProfileError(
            "%s member sequence differs from the closed profile" % location
        )
    summary = {
        "member_count": len(records),
        "uncompressed_byte_count": total,
        "member_manifest_sha256": canonical_sha256(records),
    }
    return members, summary


def _relationship_source(part: str, member_names: set[str]) -> str:
    if part == "_rels/.rels":
        return ""
    marker = "/_rels/"
    if marker not in part or not part.endswith(".rels"):
        raise ProfileError("malformed relationship-part path %s" % part)
    prefix, suffix = part.split(marker, 1)
    if not suffix or "/" in suffix or suffix == ".rels":
        raise ProfileError("malformed relationship-part path %s" % part)
    source = prefix + "/" + suffix[:-5]
    if source not in member_names:
        raise ProfileError("relationship source is absent: %s" % source)
    return source


def _resolve_internal_target(source: str, target: str) -> str:
    if (
        not target
        or "\\" in target
        or any(ord(character) < 0x20 for character in target)
        or target != target.strip()
    ):
        raise ProfileError("unsafe internal relationship target")
    parsed = urllib.parse.urlsplit(target)
    if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment:
        raise ProfileError("internal relationship target is not a package path")
    if target.startswith("/"):
        combined = target[1:]
    else:
        combined = posixpath.join(posixpath.dirname(source), target)
    normalized = posixpath.normpath(combined)
    if normalized in {"", ".", ".."} or normalized.startswith("../"):
        raise ProfileError("relationship target escapes the package")
    return _safe_member_name(normalized)


def validate_relationships(
    members: Mapping[str, bytes], location: str
) -> tuple[list[dict[str, Any]], dict[tuple[str, str], dict[str, str]]]:
    names = set(members)
    records: list[dict[str, Any]] = []
    index: dict[tuple[str, str], dict[str, str]] = {}
    for part in sorted(name for name in names if name.endswith(".rels")):
        source = _relationship_source(part, names)
        root = _parse_xml(members[part], location + ":" + part)
        if root.tag != P + "Relationships" or root.attrib:
            raise ProfileError("relationship root is outside the closed grammar")
        seen: set[str] = set()
        for element in root:
            if element.tag != P + "Relationship" or list(element):
                raise ProfileError("unexpected relationship XML element")
            allowed_attrs = {"Id", "Type", "Target", "TargetMode"}
            if not set(element.attrib).issubset(allowed_attrs):
                raise ProfileError("unexpected relationship attribute")
            rel_id = element.attrib.get("Id", "")
            rel_type = element.attrib.get("Type", "")
            target = element.attrib.get("Target", "")
            mode = element.attrib.get("TargetMode")
            if REL_ID_RE.fullmatch(rel_id) is None or rel_id in seen:
                raise ProfileError("invalid or duplicate relationship ID")
            seen.add(rel_id)
            if rel_type not in ALLOWED_REL_TYPES:
                raise ProfileError("unapproved relationship type")
            if mode is None:
                resolved = _resolve_internal_target(source, target)
                if resolved not in names:
                    raise ProfileError("relationship target is absent: %s" % resolved)
            else:
                if mode != "External" or rel_type != HYPERLINK_REL:
                    raise ProfileError("unapproved external relationship")
                parsed = urllib.parse.urlsplit(target)
                if (
                    target not in EXTERNAL_HYPERLINKS
                    or parsed.scheme not in {"http", "mailto"}
                    or target != target.strip()
                    or any(ord(character) < 0x20 for character in target)
                ):
                    raise ProfileError("external hyperlink is outside the allowlist")
                resolved = target
            record = {
                "part": part,
                "source": source,
                "id": rel_id,
                "type": rel_type,
                "target": target,
                "target_mode": mode,
                "resolved_target": resolved,
            }
            records.append(record)
            index[(source, rel_id)] = record
    return records, index


def validate_content_types(
    members: Mapping[str, bytes], location: str
) -> list[dict[str, str]]:
    part = "[Content_Types].xml"
    if part not in members:
        raise ProfileError("OOXML content-types part is absent")
    root = _parse_xml(members[part], location + ":" + part)
    if root.tag != CT + "Types" or root.attrib:
        raise ProfileError("content-types root is outside the closed grammar")
    defaults: dict[str, str] = {}
    overrides: dict[str, str] = {}
    records: list[dict[str, str]] = []
    for element in root:
        if list(element):
            raise ProfileError("content-type records must be empty elements")
        if element.tag == CT + "Default":
            if set(element.attrib) != {"Extension", "ContentType"}:
                raise ProfileError("invalid content-type Default attributes")
            key = element.attrib["Extension"]
            if not key or key in defaults or key.lower() != key:
                raise ProfileError("invalid or duplicate default extension")
            defaults[key] = element.attrib["ContentType"]
            records.append(
                {"kind": "Default", "key": key, "type": defaults[key]}
            )
        elif element.tag == CT + "Override":
            if set(element.attrib) != {"PartName", "ContentType"}:
                raise ProfileError("invalid content-type Override attributes")
            raw = element.attrib["PartName"]
            if not raw.startswith("/"):
                raise ProfileError("override PartName is not package-absolute")
            key = _safe_member_name(raw[1:])
            if key in overrides or key not in members:
                raise ProfileError("invalid, duplicate, or absent override part")
            overrides[key] = element.attrib["ContentType"]
            records.append(
                {"kind": "Override", "key": key, "type": overrides[key]}
            )
        else:
            raise ProfileError("unexpected content-type element")
    for name in members:
        if name == part:
            continue
        extension = name.rsplit(".", 1)[-1].lower() if "." in name else ""
        if name not in overrides and extension not in defaults:
            raise ProfileError("package member has no content type: %s" % name)
    return records


def _flatten_shared_string(element: ET.Element) -> str:
    if element.tag != M + "si" or element.attrib:
        raise ProfileError("shared string item is outside the closed grammar")
    children = list(element)
    if len(children) == 1 and children[0].tag == M + "t":
        runs = [children[0]]
    elif children and all(child.tag == M + "r" for child in children):
        runs = []
        allowed_rpr = {
            M + name
            for name in (
                "b",
                "i",
                "strike",
                "outline",
                "shadow",
                "condense",
                "extend",
                "color",
                "sz",
                "u",
                "vertAlign",
                "rFont",
                "family",
                "charset",
                "scheme",
            )
        }
        for run in children:
            if run.attrib:
                raise ProfileError("rich-text run has unexpected attributes")
            run_children = list(run)
            if not run_children or run_children[-1].tag != M + "t":
                raise ProfileError("rich-text run lacks a terminal text node")
            if len(run_children) > 2:
                raise ProfileError("rich-text run has unexpected children")
            if len(run_children) == 2:
                rpr = run_children[0]
                if rpr.tag != M + "rPr" or rpr.attrib:
                    raise ProfileError("rich-text properties are malformed")
                for property_element in rpr:
                    if property_element.tag not in allowed_rpr or list(
                        property_element
                    ):
                        raise ProfileError("unapproved rich-text property")
            runs.append(run_children[-1])
    else:
        raise ProfileError("shared string has an unapproved representation")
    text_parts: list[str] = []
    for text_element in runs:
        if set(text_element.attrib) - {"{%s}space" % XML_NS}:
            raise ProfileError("shared-string text has unexpected attributes")
        space = text_element.attrib.get("{%s}space" % XML_NS)
        if space not in {None, "preserve"}:
            raise ProfileError("invalid xml:space value")
        text_parts.append(text_element.text or "")
    return "".join(text_parts)


def _core_properties(members: Mapping[str, bytes], location: str) -> dict[str, str]:
    root = _parse_xml(members["docProps/core.xml"], location + ":core.xml")
    if root.tag != "{%s}coreProperties" % CORE_NS:
        raise ProfileError("invalid core-properties root")
    result: dict[str, str] = {}
    names = {
        "{%s}creator" % DC_NS: "creator",
        "{%s}lastModifiedBy" % CORE_NS: "lastModifiedBy",
        "{%s}lastPrinted" % CORE_NS: "lastPrinted",
        "{%s}created" % DCTERMS_NS: "created",
        "{%s}modified" % DCTERMS_NS: "modified",
    }
    for element in root:
        key = names.get(element.tag)
        if key is None or key in result or list(element):
            raise ProfileError("unapproved core property")
        result[key] = element.text or ""
    return result


def _parse_styles(members: Mapping[str, bytes], location: str) -> list[int]:
    root = _parse_xml(members["xl/styles.xml"], location + ":styles.xml")
    if root.tag != M + "styleSheet":
        raise ProfileError("invalid styles root")
    cell_xfs = root.find(M + "cellXfs")
    if cell_xfs is None:
        raise ProfileError("styles part lacks cellXfs")
    xfs = list(cell_xfs)
    count = _uint(cell_xfs.attrib.get("count", ""), "cellXfs count")
    if count != len(xfs) or not xfs:
        raise ProfileError("cellXfs count mismatch")
    result: list[int] = []
    for xf in xfs:
        if xf.tag != M + "xf":
            raise ProfileError("unexpected cellXfs child")
        num_fmt_id = _uint(xf.attrib.get("numFmtId", ""), "xf numFmtId")
        result.append(num_fmt_id)
    return result


def _parse_cells(
    data: bytes,
    part: str,
    shared_strings: Sequence[str],
    num_formats: Sequence[int],
) -> tuple[str, dict[str, Cell], int]:
    root = _parse_xml(data, part)
    if root.tag != M + "worksheet":
        raise ProfileError("worksheet part has an invalid root")
    dimension = root.find(M + "dimension")
    if dimension is None or set(dimension.attrib) != {"ref"}:
        raise ProfileError("worksheet dimension is absent or malformed")
    sheet_data = root.find(M + "sheetData")
    if sheet_data is None:
        raise ProfileError("worksheet lacks sheetData")
    cells: dict[str, Cell] = {}
    shared_uses = 0
    seen_rows: set[int] = set()
    previous_row = 0
    for row_element in sheet_data:
        if row_element.tag != M + "row":
            raise ProfileError("unexpected sheetData child")
        row_number = _uint(row_element.attrib.get("r", ""), part + " row")
        if row_number in seen_rows or row_number <= previous_row:
            raise ProfileError("worksheet rows are duplicate or unordered")
        previous_row = row_number
        seen_rows.add(row_number)
        previous_column = 0
        for element in row_element:
            if element.tag != M + "c":
                raise ProfileError("unexpected worksheet row child")
            reference = element.attrib.get("r", "")
            cell_row, cell_column = _cell_coordinates(reference)
            if cell_row != row_number or cell_column <= previous_column:
                raise ProfileError("worksheet cells are misplaced or unordered")
            previous_column = cell_column
            if reference in cells:
                raise ProfileError("duplicate worksheet cell reference")
            if set(element.attrib) - {"r", "s", "t"}:
                raise ProfileError("cell has an unapproved attribute")
            style_index = _uint(element.attrib.get("s", "0"), reference + " style")
            if style_index >= len(num_formats):
                raise ProfileError("cell style index is out of bounds")
            cell_type = element.attrib.get("t")
            if cell_type not in {None, "s", "e"}:
                raise ProfileError("cell type is outside the closed profile")
            values = element.findall(M + "v")
            formulas = element.findall(M + "f")
            if len(values) > 1 or len(formulas) > 1:
                raise ProfileError("cell has duplicate value/formula elements")
            if any(child.tag not in {M + "f", M + "v"} for child in element):
                raise ProfileError("cell has an unapproved child element")
            if formulas and list(element)[0].tag != M + "f":
                raise ProfileError("formula is not the first cell child")
            value = values[0].text if values else None
            formula = (formulas[0].text or "") if formulas else None
            if formulas and formulas[0].attrib:
                raise ProfileError("formula attributes are forbidden")
            if cell_type == "s":
                if value is None:
                    raise ProfileError("shared-string cell lacks an index")
                index = _uint(value, reference + " shared-string index")
                if index >= len(shared_strings):
                    raise ProfileError("shared-string index is out of bounds")
                shared_uses += 1
            elif cell_type == "e" and value is None:
                raise ProfileError("error cell lacks a cached error token")
            cells[reference] = Cell(
                reference,
                cell_row,
                cell_column,
                cell_type,
                style_index,
                value,
                formula,
            )
    return dimension.attrib["ref"], cells, shared_uses


def _resolved_text(view: WorkbookView, sheet: str, reference: str) -> str | None:
    cell = view.sheets[sheet].get(reference)
    if cell is None or cell.value is None:
        return None
    if cell.formula is not None:
        raise ProfileError("formula cell cannot be resolved as source text")
    if cell.cell_type == "s":
        return view.shared_strings[_uint(cell.value, reference + " index")]
    if cell.cell_type is None:
        return cell.value
    raise ProfileError("cell is not source text")


def _require_text(
    view: WorkbookView, sheet: str, reference: str, expected: str
) -> None:
    actual = _resolved_text(view, sheet, reference)
    if actual != expected:
        raise ProfileError("%s!%s text mismatch" % (sheet, reference))


def _code(view: WorkbookView, sheet: str, reference: str) -> str:
    value = _resolved_text(view, sheet, reference)
    if value is None or CODE_RE.fullmatch(value) is None:
        raise ProfileError("%s!%s is not a canonical source code" % (sheet, reference))
    return value


def _integer(
    view: WorkbookView, sheet: str, row: int, column: int
) -> tuple[int | None, str]:
    reference = column_name(column) + str(row)
    cell = view.sheets[sheet].get(reference)
    if cell is None:
        return None, "ABSENT"
    if cell.formula is not None or cell.cell_type is not None:
        raise ProfileError("logical numeric cell has nonnumeric type/formula")
    if view.num_formats[cell.style_index] not in {0, 3}:
        raise ProfileError("logical numeric cell has an unapproved number format")
    if cell.value is None:
        return None, "BLANK"
    if INT_RE.fullmatch(cell.value) is None:
        raise ProfileError("logical numeric cell violates exact integer grammar")
    return int(cell.value), cell.value


def _logical_digest(
    view: WorkbookView,
    sheet_names: Iterable[str],
    row_start: int,
    row_end: int,
    column_start: int,
    column_end: int,
) -> tuple[str, dict[str, int]]:
    records: list[list[Any]] = []
    counts = {"integer": 0, "blank": 0, "absent": 0}
    for sheet in sheet_names:
        for row in range(row_start, row_end + 1):
            for column in range(column_start, column_end + 1):
                value, token = _integer(view, sheet, row, column)
                if value is not None:
                    counts["integer"] += 1
                elif token == "BLANK":
                    counts["blank"] += 1
                else:
                    counts["absent"] += 1
                cell = view.sheets[sheet].get(column_name(column) + str(row))
                records.append(
                    [
                        sheet,
                        row,
                        column,
                        token,
                        None if cell is None else cell.style_index,
                        None
                        if cell is None
                        else view.num_formats[cell.style_index],
                    ]
                )
    return canonical_sha256(records), counts


def _validate_formulas(view: WorkbookView) -> list[dict[str, Any]]:
    observed: list[dict[str, Any]] = []
    for sheet_name, cells in view.sheets.items():
        for cell in cells.values():
            if cell.formula is not None or cell.cell_type == "e":
                observed.append(
                    {
                        "sheet": sheet_name,
                        "cell": cell.reference,
                        "formula": cell.formula,
                        "cached_value": cell.value,
                        "cell_type": cell.cell_type,
                        "style_index": cell.style_index,
                    }
                )
    expected: list[dict[str, Any]] = []
    if view.spec.kind == "detail_use":
        for row in range(337, 345):
            expected.append(
                {
                    "sheet": "2007",
                    "cell": "OP%d" % row,
                    "formula": "#REF!-SUM(C%d:OA%d,OC%d:OM%d)"
                    % (row, row, row, row),
                    "cached_value": "#REF!",
                    "cell_type": "e",
                    "style_index": 11,
                }
            )
    if sorted(observed, key=lambda item: (item["sheet"], item["cell"])) != expected:
        raise ProfileError("formula/error set differs from the exact exception")
    if expected:
        if column_number("OP") <= column_number("ON"):
            raise ProfileError("orphan formula column is not outside logical evidence")
        if _resolved_text(view, "2007", "OP6") is not None:
            raise ProfileError(
                "orphan formula column unexpectedly has a logical header"
            )
    return expected


def inspect_workbook(data: bytes, spec: WorkbookSpec) -> WorkbookView:
    members, zip_summary = validate_zip_bytes(data, spec.filename)
    relationships, relationship_index = validate_relationships(members, spec.filename)
    content_types = validate_content_types(members, spec.filename)
    required = {
        "xl/workbook.xml",
        "xl/_rels/workbook.xml.rels",
        "xl/sharedStrings.xml",
        "xl/styles.xml",
        "docProps/core.xml",
    }
    if not required.issubset(members):
        raise ProfileError("workbook lacks required OOXML parts")
    shared_root = _parse_xml(
        members["xl/sharedStrings.xml"], spec.filename + ":sharedStrings.xml"
    )
    if shared_root.tag != M + "sst":
        raise ProfileError("invalid sharedStrings root")
    if set(shared_root.attrib) != {"count", "uniqueCount"}:
        raise ProfileError("sharedStrings root attributes differ from the profile")
    shared_strings = [_flatten_shared_string(item) for item in shared_root]
    unique_count = _uint(
        shared_root.attrib.get("uniqueCount", ""), "sharedStrings uniqueCount"
    )
    declared_count = _uint(
        shared_root.attrib.get("count", ""), "sharedStrings count"
    )
    if unique_count != len(shared_strings):
        raise ProfileError("sharedStrings uniqueCount mismatch")
    num_formats = _parse_styles(members, spec.filename)
    workbook_root = _parse_xml(
        members["xl/workbook.xml"], spec.filename + ":workbook.xml"
    )
    if workbook_root.tag != M + "workbook":
        raise ProfileError("invalid workbook root")
    sheets_element = workbook_root.find(M + "sheets")
    if sheets_element is None:
        raise ProfileError("workbook lacks sheets")
    sheets: dict[str, dict[str, Cell]] = {}
    sheet_parts: dict[str, str] = {}
    sheet_records: list[dict[str, Any]] = []
    shared_uses = 0
    seen_sheet_ids: set[int] = set()
    for position, sheet_element in enumerate(sheets_element, start=1):
        if sheet_element.tag != M + "sheet":
            raise ProfileError("unexpected workbook sheets child")
        if set(sheet_element.attrib) - {"name", "sheetId", REL_ID, "state"}:
            raise ProfileError("sheet has unexpected attributes")
        name = sheet_element.attrib.get("name", "")
        sheet_id = _uint(sheet_element.attrib.get("sheetId", ""), "sheetId")
        rel_id = sheet_element.attrib.get(REL_ID, "")
        if (
            name in sheets
            or sheet_id in seen_sheet_ids
            or sheet_element.attrib.get("state") not in {None, "visible"}
        ):
            raise ProfileError("duplicate or hidden sheet")
        seen_sheet_ids.add(sheet_id)
        relation = relationship_index.get(("xl/workbook.xml", rel_id))
        if relation is None or relation["type"] != WORKSHEET_REL:
            raise ProfileError("sheet relationship is absent or mistyped")
        part = relation["resolved_target"]
        dimension, cells, uses = _parse_cells(
            members[part], part, shared_strings, num_formats
        )
        sheets[name] = cells
        sheet_parts[name] = part
        shared_uses += uses
        sheet_records.append(
            {
                "position": position,
                "name": name,
                "sheet_id": sheet_id,
                "relationship_id": rel_id,
                "part": part,
                "dimension": dimension,
                "part_sha256": sha256_bytes(members[part]),
            }
        )
    if tuple(sheets) != spec.sheets:
        raise ProfileError("workbook sheet order/name set differs from the profile")
    if tuple(item["dimension"] for item in sheet_records) != spec.dimensions:
        raise ProfileError("worksheet dimensions differ from the profile")
    if declared_count != shared_uses:
        raise ProfileError("sharedStrings count does not equal actual cell uses")
    core = _core_properties(members, spec.filename)
    if tuple(core.items()) != spec.core_properties:
        raise ProfileError("core properties differ from the profile")
    view = WorkbookView(spec, shared_strings, num_formats, sheets, sheet_parts, {})
    _require_text(view, "ReadMe", spec.readme_cell, spec.readme_text)
    formulas = _validate_formulas(view)
    if spec.kind == "detail_use":
        chain = members.get("xl/calcChain.xml")
        if chain is None:
            raise ProfileError("detail-use formula exception lacks calcChain")
        chain_root = _parse_xml(chain, spec.filename + ":calcChain.xml")
        chain_cells = [
            {"reference": item.attrib.get("r"), "sheet_index": item.attrib.get("i")}
            for item in chain_root
        ]
        if {item["reference"] for item in chain_cells} != {
            "OP%d" % row for row in range(337, 345)
        } or {item["sheet_index"] for item in chain_cells} != {"1"}:
            raise ProfileError("calcChain differs from the orphan-formula exception")
    elif "xl/calcChain.xml" in members:
        raise ProfileError("unexpected calcChain in formula-free workbook")
    structure = {
        "zip": zip_summary,
        "member_content_manifest_sha256": canonical_sha256(
            [
                [name, len(payload), sha256_bytes(payload)]
                for name, payload in sorted(members.items())
            ]
        ),
        "relationship_count": len(relationships),
        "relationship_manifest_sha256": canonical_sha256(relationships),
        "content_type_manifest_sha256": canonical_sha256(content_types),
        "sheet_manifest_sha256": canonical_sha256(sheet_records),
        "sheet_count": len(sheet_records),
        "shared_string_count": declared_count,
        "shared_string_unique_count": unique_count,
        "shared_string_manifest_sha256": canonical_sha256(shared_strings),
        "styles_part_sha256": sha256_bytes(members["xl/styles.xml"]),
        "cell_xf_count": len(num_formats),
        "cell_xf_num_fmt_manifest_sha256": canonical_sha256(num_formats),
        "core_properties": core,
        "formula_exception": formulas,
        "formula_exception_outside_logical_range": bool(formulas),
    }
    if spec.kind == "detail_use":
        structure["formula_evidence_boundary"] = {
            "sheet": "2007",
            "logical_last_column": "ON",
            "logical_total_code": "T007",
            "intervening_unlabelled_column": "OO",
            "orphan_formula_column": "OP",
            "orphan_column_header": None,
            "formula_cells_are_source_evidence": False,
        }
    view.structure = structure
    return view


def _axis(
    view: WorkbookView, sheet: str, references: Sequence[str]
) -> tuple[str, ...]:
    return tuple(_code(view, sheet, reference) for reference in references)


def _validate_summary(view: WorkbookView) -> dict[str, Any]:
    if view.spec.kind == "summary_make":
        for sheet in YEAR_SHEETS:
            rows = _axis(view, sheet, ["A%d" % row for row in range(7, 76)])
            columns = _axis(
                view, sheet, [column_name(column) + "6" for column in range(3, 72)]
            )
            if rows != SUMMARY_CODES or columns != SUMMARY_CODES:
                raise ProfileError("summary-make ordinary axis mismatch")
            if _axis(view, sheet, ("BT6", "BU6", "BV6", "A76")) != (
                "Used",
                "Other",
                "T008",
                "T007",
            ):
                raise ProfileError("summary-make terminal mapping mismatch")
        digest, counts = _logical_digest(view, YEAR_SHEETS, 7, 76, 3, 74)
    else:
        for sheet in YEAR_SHEETS:
            rows = _axis(view, sheet, ["A%d" % row for row in range(7, 76)])
            columns = _axis(
                view, sheet, [column_name(column) + "6" for column in range(3, 72)]
            )
            if rows != SUMMARY_CODES or columns != SUMMARY_CODES:
                raise ProfileError("summary-use ordinary axis mismatch")
            if _axis(view, sheet, ("A76", "A77")) != ("Used", "Other"):
                raise ProfileError("summary-use special rows mismatch")
            if _axis(
                view,
                sheet,
                ("BT6",)
                + tuple(column_name(column) + "6" for column in range(73, 84))
                + ("CF6", "CG6"),
            ) != ("T001",) + SUMMARY_FINAL_USE_CODES + ("T004", "T007"):
                raise ProfileError("summary-use terminal columns mismatch")
            if _axis(
                view,
                sheet,
                tuple("A%d" % row for row in range(78, 84)),
            ) != ("T005", "V001", "V002", "V003", "T006", "T008"):
                raise ProfileError("summary-use value-added rows mismatch")
            _require_text(
                view, sheet, "B76", "Scrap, used and secondhand goods"
            )
            _require_text(
                view,
                sheet,
                "B77",
                "Noncomparable imports and rest-of-the-world adjustment1",
            )
        digest, counts = _logical_digest(view, YEAR_SHEETS, 7, 83, 3, 85)
    return {
        "years": list(YEAR_SHEETS),
        "annual_axis_complete": True,
        "ordinary_axis_count": 69,
        "ordinary_axis_sha256": canonical_sha256(SUMMARY_CODES),
        "logical_cells_sha256": digest,
        "logical_cell_counts": counts,
    }


def _validate_crosswalk(view: WorkbookView) -> dict[str, Any]:
    expected = {
        "B476": "531",
        "C476": "Real estate",
        "C478": "531000",
        "D478": "Real estate",
        "F478": "531",
        "B610": "GFG",
        "C610": "Federal general government",
        "C612": "S00500",
        "D612": "Federal general government (defense)",
        "C613": "S00600",
        "D613": "Federal general government (nondefense)",
        "A631": "Used",
        "B631": "Scrap, used and secondhand goods",
        "C635": "S00401",
        "D635": "Scrap",
        "C636": "S00402",
        "D636": "Used and secondhand goods",
        "A638": "Other",
        "B638": "Noncomparable imports and rest-of-the-world adjustment",
        "C642": "S00300",
        "D642": "Noncomparable imports",
        "C643": "S00900",
        "D643": "Rest of the world adjustment",
    }
    for reference, text in expected.items():
        _require_text(view, "NAICS codes", reference, text)
    return {
        "mapping_cells_sha256": canonical_sha256(expected),
        "used_components": ["S00401", "S00402"],
        "other_components": ["S00300", "S00900"],
        "summary_531_detail_code": "531000",
        "summary_gfg_detail_codes": ["S00500", "S00600"],
    }


def _validate_detail(view: WorkbookView) -> dict[str, Any]:
    sheet = "2007"
    rows = _axis(view, sheet, ["A%d" % row for row in range(7, 395)])
    columns = _axis(
        view, sheet, [column_name(column) + "6" for column in range(3, 391)]
    )
    if len(rows) != 388 or len(set(rows)) != 388:
        raise ProfileError("detail row axis is not exactly 388 unique codes")
    if len(columns) != 388 or len(set(columns)) != 388:
        raise ProfileError("detail column axis is not exactly 388 unique codes")
    if view.spec.kind == "detail_make":
        if tuple(columns[-4:]) != DETAIL_SPECIAL_CODES:
            raise ProfileError("detail-make special commodity columns mismatch")
        if _code(view, sheet, "OA6") != "T008" or _code(
            view, sheet, "A395"
        ) != "T007":
            raise ProfileError("detail-make terminal mapping mismatch")
        digest, counts = _logical_digest(view, (sheet,), 7, 395, 3, 391)
    else:
        if tuple(rows[-4:]) != DETAIL_SPECIAL_CODES:
            raise ProfileError("detail-use special commodity rows mismatch")
        if _code(view, sheet, "OA6") != "T001" or _code(
            view, sheet, "OM6"
        ) != "T004" or _code(view, sheet, "ON6") != "T007":
            raise ProfileError("detail-use terminal mapping mismatch")
        if _axis(
            view,
            sheet,
            tuple("A%d" % row for row in range(395, 401)),
        ) != ("T005", "V00100", "V00200", "V00300", "T006", "T008"):
            raise ProfileError("detail-use value-added rows mismatch")
        digest, counts = _logical_digest(view, (sheet,), 7, 400, 3, 404)
    if rows.count("531000") != 1 or columns.count("531000") != 1:
        raise ProfileError("detail real-estate axis is not the single combined 531000")
    if any(code.startswith("531") for code in rows if code != "531000") or any(
        code.startswith("531") for code in columns if code != "531000"
    ):
        raise ProfileError("detail workbook unexpectedly splits real estate")
    expected_federal = {"S00500", "S00600", "491000", "S00102"}
    if not expected_federal.issubset(rows) or not expected_federal.issubset(columns):
        raise ProfileError("detail federal witness is incomplete")
    crosswalk = _validate_crosswalk(view)
    return {
        "row_axis_sha256": canonical_sha256(rows),
        "column_axis_sha256": canonical_sha256(columns),
        "row_axis_count": len(rows),
        "column_axis_count": len(columns),
        "logical_cells_sha256": digest,
        "logical_cell_counts": counts,
        "single_combined_real_estate_code": "531000",
        "federal_components_present": sorted(expected_federal),
        "crosswalk": crosswalk,
        "row_axis": rows,
        "column_axis": columns,
    }


def _sum_present(values: Iterable[int | None]) -> int:
    return sum(0 if value is None else value for value in values)


def _value(view: WorkbookView, sheet: str, row: int, column: int) -> int:
    value, _ = _integer(view, sheet, row, column)
    if value is None:
        return 0
    return value


def _accounting_diagnostics(
    summary_make: WorkbookView,
    summary_use: WorkbookView,
    detail_make: WorkbookView,
    detail_use: WorkbookView,
) -> dict[str, Any]:
    diagnostics: list[dict[str, Any]] = []
    limits = {
        "make_industry_row": 4,
        "make_commodity_column": 4,
        "use_intermediate_row": 8,
        "use_final_row": 2,
        "use_total_commodity_row": 1,
        "use_intermediate_column": 7,
        "use_value_added_column": 1,
        "use_output_column": 1,
        "cross_commodity_output": 0,
        "cross_industry_output": 1,
    }
    maxima = {key: 0 for key in limits}

    def record(kind: str, year: str, coordinate: str, residual: int) -> None:
        maxima[kind] = max(maxima[kind], abs(residual))
        diagnostics.append(
            {"kind": kind, "year": year, "coordinate": coordinate, "residual": residual}
        )

    for year in YEAR_SHEETS:
        for row in range(7, 76):
            record(
                "make_industry_row",
                year,
                "row%d" % row,
                _sum_present(
                    _value(summary_make, year, row, column)
                    for column in range(3, 74)
                )
                - _value(summary_make, year, row, 74),
            )
        for column in range(3, 74):
            record(
                "make_commodity_column",
                year,
                column_name(column),
                _sum_present(
                    _value(summary_make, year, row, column)
                    for row in range(7, 76)
                )
                - _value(summary_make, year, 76, column),
            )
        for row in range(7, 78):
            record(
                "use_intermediate_row",
                year,
                "row%d" % row,
                _sum_present(
                    _value(summary_use, year, row, column)
                    for column in range(3, 72)
                )
                - _value(summary_use, year, row, 72),
            )
            record(
                "use_final_row",
                year,
                "row%d" % row,
                _sum_present(
                    _value(summary_use, year, row, column)
                    for column in range(73, 84)
                )
                - _value(summary_use, year, row, 84),
            )
            record(
                "use_total_commodity_row",
                year,
                "row%d" % row,
                _value(summary_use, year, row, 72)
                + _value(summary_use, year, row, 84)
                - _value(summary_use, year, row, 85),
            )
        for column in range(3, 72):
            record(
                "use_intermediate_column",
                year,
                column_name(column),
                _sum_present(
                    _value(summary_use, year, row, column)
                    for row in range(7, 78)
                )
                - _value(summary_use, year, 78, column),
            )
            record(
                "use_value_added_column",
                year,
                column_name(column),
                _sum_present(
                    _value(summary_use, year, row, column)
                    for row in range(79, 82)
                )
                - _value(summary_use, year, 82, column),
            )
            record(
                "use_output_column",
                year,
                column_name(column),
                _value(summary_use, year, 78, column)
                + _value(summary_use, year, 82, column)
                - _value(summary_use, year, 83, column),
            )
        for offset in range(71):
            record(
                "cross_commodity_output",
                year,
                "commodity%d" % (offset + 1),
                _value(summary_make, year, 76, 3 + offset)
                - _value(summary_use, year, 7 + offset, 85),
            )
        for offset in range(69):
            record(
                "cross_industry_output",
                year,
                "industry%d" % (offset + 1),
                _value(summary_make, year, 7 + offset, 74)
                - _value(summary_use, year, 83, 3 + offset),
            )
    for kind, limit in limits.items():
        if maxima[kind] > limit:
            raise ProfileError(
                "published-rounding accounting bound exceeded: %s" % kind
            )

    def axis_index(view: WorkbookView, on_rows: bool, code: str) -> int:
        references = (
            ["A%d" % row for row in range(7, 395)]
            if on_rows
            else [column_name(column) + "6" for column in range(3, 391)]
        )
        codes = [_code(view, "2007", reference) for reference in references]
        return codes.index(code) + (7 if on_rows else 3)

    component_checks: dict[str, dict[str, int]] = {}
    for label, components in {
        "Used": ("S00401", "S00402"),
        "Other": ("S00300", "S00900"),
    }.items():
        summary_row = 76 if label == "Used" else 77
        summary_column = 72 if label == "Used" else 73
        detail_columns = [axis_index(detail_make, False, code) for code in components]
        detail_rows = [axis_index(detail_use, True, code) for code in components]
        values = {
            "summary_output": _value(summary_use, "2007", summary_row, 85),
            "summary_make_output": _value(summary_make, "2007", 76, summary_column),
            "detail_make_component_output": _sum_present(
                _value(detail_make, "2007", 395, column)
                for column in detail_columns
            ),
            "detail_use_component_output": _sum_present(
                _value(detail_use, "2007", row, 404) for row in detail_rows
            ),
        }
        if len(set(values.values())) != 1:
            raise ProfileError("detail special components do not reconcile to summary")
        component_checks[label] = values

    detail_make_rows = _axis(
        detail_make, "2007", ["A%d" % row for row in range(7, 395)]
    )
    detail_use_columns = _axis(
        detail_use,
        "2007",
        [column_name(column) + "6" for column in range(3, 391)],
    )
    detail_make_columns = _axis(
        detail_make,
        "2007",
        [column_name(column) + "6" for column in range(3, 391)],
    )
    detail_use_rows = _axis(
        detail_use, "2007", ["A%d" % row for row in range(7, 395)]
    )
    if detail_make_rows != detail_use_columns or detail_make_columns != detail_use_rows:
        raise ProfileError("detail make/use axes do not transpose exactly")

    federal_rows = [detail_make_rows.index(code) + 7 for code in ("S00500", "S00600")]
    summary_gfg_row = SUMMARY_CODES.index("GFG") + 7
    federal_output = _sum_present(
        _value(detail_make, "2007", row, 391) for row in federal_rows
    )
    summary_gfg_output = _value(summary_make, "2007", summary_gfg_row, 74)
    if federal_output != summary_gfg_output:
        raise ProfileError("federal defense/nondefense witness does not reconcile")

    real_estate_row = detail_make_rows.index("531000") + 7
    summary_531_row = SUMMARY_CODES.index("531") + 7
    detail_531_output = _value(detail_make, "2007", real_estate_row, 391)
    summary_531_output = _value(summary_make, "2007", summary_531_row, 74)
    if detail_531_output != summary_531_output:
        raise ProfileError("combined detail/summary real-estate output differs")

    return {
        "arbitrary_precision_integer_arithmetic": True,
        "published_rounding_rebalance_applied": False,
        "rounding_residual_limits": limits,
        "observed_maximum_absolute_residuals": maxima,
        "diagnostic_manifest_sha256": canonical_sha256(diagnostics),
        "special_component_checks_2007": component_checks,
        "federal_gfg_check_2007": {
            "detail_S00500_plus_S00600": federal_output,
            "summary_GFG": summary_gfg_output,
        },
        "real_estate_check_2007": {
            "detail_531000": detail_531_output,
            "summary_531": summary_531_output,
            "HS_ORE_split_identified": False,
        },
    }


def _validate_metadata(payloads: Mapping[str, bytes]) -> dict[str, Any]:
    root = parse_json(payloads["hmi8-root.json"], "hmi8-root.json")
    path_id = parse_json(payloads["url-path-id.json"], "url-path-id.json")
    path = parse_json(payloads["get-path.json"], "get-path.json")
    files = parse_json(payloads["release-files.json"], "release-files.json")
    if not isinstance(root, dict) or not isinstance(files, dict):
        raise ProfileError("HMI8 metadata roots have unexpected types")
    if path_id != [
        {
            "Notes": None,
            "Theid": DIRECTORY_ID,
            "Thepath": None,
            "DescriptionLong": None,
        }
    ]:
        raise ProfileError("path-to-ID metadata mismatch")
    expected_server_path = (
        "/Inetpub/wwwroot/website/website/HistData/Files/Releases/Industry\\"
        + DIRECTORY.replace("/", "\\")
    )
    if path != [
        {
            "Notes": None,
            "Theid": None,
            "Thepath": expected_server_path,
            "DescriptionLong": None,
        }
    ]:
        raise ProfileError("ID-to-path metadata mismatch")
    expected_files = [
        expected_server_path + "\\" + name
        for name in ("WhatsNew.inc", "AllTablesIO.zip", "AllTables.zip")
    ]
    if (
        files.get("FileArray") != expected_files
        or files.get("Filearray3") != expected_files
    ):
        raise ProfileError("release file-list metadata mismatch")
    description = files.get("DescriptionLong")
    if not isinstance(description, str) or (
        "Input-output statistics were not archived prior to the release on "
        "January 23, 2014." not in description
    ):
        raise ProfileError("release file-list archive statement is absent")
    root_files = root.get("FileArray")
    if not isinstance(root_files, list) or not any(
        isinstance(item, str)
        and item.replace("\\", "/").endswith("Industry/" + DIRECTORY)
        for item in root_files
    ):
        raise ProfileError("HMI8 root does not contain the pinned release directory")
    root_description = root.get("DescriptionLong")
    if not isinstance(root_description, str) or (
        "Input-output statistics were not archived prior to the release on "
        "January 23, 2014." not in root_description
    ):
        raise ProfileError("HMI8 root archive statement is absent")
    return {
        "directory": DIRECTORY,
        "directory_id": DIRECTORY_ID,
        "file_names": ["WhatsNew.inc", "AllTablesIO.zip", "AllTables.zip"],
        "date_only_release_identity": RELEASE_DATE,
        "intraday_release_time_present": False,
        "availability_ceiling": RELEASE_AVAILABILITY_CEILING,
        "semantic_manifest_sha256": canonical_sha256(
            {
                "root_file_count": len(root_files),
                "directory": DIRECTORY,
                "directory_id": DIRECTORY_ID,
                "release_files": expected_files,
            }
        ),
    }


def build_artifact(
    capture_dir: Path, workbook_dir: Path, *, enforce_frozen: bool = True
) -> dict[str, Any]:
    if enforce_frozen:
        _validate_contract()
    capture_payloads = {
        spec.name: _read_regular_file(capture_dir / spec.name, spec)
        for spec in CAPTURE_SPECS
    }
    metadata = _validate_metadata(capture_payloads)
    io_members, io_archive = validate_zip_bytes(
        capture_payloads["AllTablesIO.zip"], "AllTablesIO.zip", OUTER_IO_MEMBERS
    )
    _, legacy_archive = validate_zip_bytes(
        capture_payloads["AllTables.zip"], "AllTables.zip", OUTER_LEGACY_MEMBERS
    )
    views: dict[str, WorkbookView] = {}
    workbook_reports: dict[str, Any] = {}
    for spec in WORKBOOK_SPECS:
        data = _read_regular_file(workbook_dir / spec.filename, spec)
        archive_data = io_members.get(spec.filename)
        if archive_data is None or archive_data != data:
            raise ProfileError(
                "extracted workbook is not byte-identical to archive member"
            )
        view = inspect_workbook(data, spec)
        if spec.kind.startswith("summary_"):
            logical = _validate_summary(view)
        else:
            logical = _validate_detail(view)
        structure = dict(view.structure)
        structure["logical_profile"] = logical
        structure_sha = canonical_sha256(structure)
        if enforce_frozen and structure_sha != spec.expected_structure_sha256:
            raise ProfileError("%s structure SHA-256 drifted" % spec.key)
        structure["structure_sha256"] = structure_sha
        workbook_reports[spec.key] = {
            "filename": spec.filename,
            "byte_count": spec.byte_count,
            "sha256": spec.sha256,
            "archive_member_byte_identical": True,
            "structure": structure,
        }
        views[spec.key] = view
    accounting = _accounting_diagnostics(
        views["summary_make"],
        views["summary_use"],
        views["detail_make"],
        views["detail_use"],
    )
    artifact = {
        "schema_version": SCHEMA_VERSION,
        "parser_version": PARSER_VERSION,
        "profile_id": PROFILE_ID,
        "status": STATUS,
        "canonicalization": CANONICALIZATION,
        "profile_contract_sha256": profile_contract_sha256(),
        "present_day_capture_timestamp_utc": PRESENT_DAY_CAPTURE_TIMESTAMP_UTC,
        "evidence_classification": {
            "byte_observation_mode": "PRESENT_DAY_ARCHIVE_RETRIEVAL",
            "information_set_construction_mode": "UNKNOWN_INFORMATION_SET",
            "candidate_use": "RECONSTRUCTED_INFORMATION_SET_PENDING_EVIDENCE",
            "release_identity": "DATE_ONLY_ASSOCIATION",
            "first_public": "UNKNOWN",
            "availability_precision": "DATE_ONLY",
            "availability_ceiling": RELEASE_AVAILABILITY_CEILING,
            "official_archive_http_last_modified": {
                "AllTablesIO.zip": "2015-03-25T14:55:20Z",
                "AllTables.zip": "2015-03-25T14:55:16Z",
            },
            "http_last_modified_evidence_status": (
                "2026_TRANSPORT_OBSERVATION_NOT_EMBEDDED_IN_PINNED_RESPONSE_BODIES"
            ),
            "blockers": [
                "bytes observed only in 2026",
                "current archive HTTP Last-Modified timestamps are in 2015",
                "detail workbooks contain a February 14, 2014 post-release edit note",
                "exact January 23, 2014 intraday public availability is unproven",
                "summary 531 cannot be split into later HS and ORE without hindsight",
            ],
        },
        "metadata": metadata,
        "outer_archives": {
            "AllTablesIO.zip": io_archive,
            "AllTables.zip": legacy_archive,
        },
        "workbooks": workbook_reports,
        "accounting": accounting,
        "mapping_decision": {
            "summary_ordinary_axis_count": 69,
            "later_axis_requires": {
                "531": ["HS", "ORE"],
                "GFG": ["GFGD", "GFGN"],
            },
            "detail_supports_federal_component_witness": True,
            "detail_real_estate_codes": ["531000"],
            "detail_supports_HS_ORE_split": False,
            "later_share_allocation_permitted": False,
            "ABM_state_emitted": False,
        },
        "gates": false_gates(),
    }
    artifact_sha = canonical_sha256(artifact)
    if enforce_frozen and artifact_sha != EXPECTED_ARTIFACT_SHA256:
        raise ProfileError("candidate artifact SHA-256 drifted")
    artifact["artifact_sha256"] = artifact_sha
    return artifact


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-dir", type=Path, required=True)
    parser.add_argument("--workbook-dir", type=Path, required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    try:
        artifact = build_artifact(arguments.capture_dir, arguments.workbook_dir)
    except ProfileError as error:
        print("FAIL_CLOSED: %s" % error, file=sys.stderr)
        return 2
    sys.stdout.buffer.write(canonical_json_bytes(artifact))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
