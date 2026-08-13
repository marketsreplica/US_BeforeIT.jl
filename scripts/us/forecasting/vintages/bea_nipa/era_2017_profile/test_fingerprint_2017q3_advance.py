#!/usr/bin/env python3
"""Adversarial tests for the closed 2017-era BEA HMI7 profile."""

from __future__ import annotations

import ast
import hashlib
import importlib.util
import io
import math
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import warnings
import xml.etree.ElementTree as ET
import zipfile
from typing import Callable, Dict, Optional, Tuple


MODULE_PATH = pathlib.Path(__file__).with_name("fingerprint_2017q3_advance.py").resolve()
SPEC = importlib.util.spec_from_file_location("bea_hmi7_era_2017", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load 2017-era parser")
ERA = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ERA
SPEC.loader.exec_module(ERA)


def repository_root() -> pathlib.Path:
    for parent in pathlib.Path(__file__).resolve().parents:
        if (parent / "US_FORECASTING_PLAN.md").is_file():
            return parent
    raise RuntimeError("repository root could not be located")


REPOSITORY = repository_root()
BUNDLE = (
    REPOSITORY
    / "data/us/raw/forecasting/bea_hmi7/advance"
    / ERA.BUNDLE_NAME
)
LATER_ERA_PARSER = (
    REPOSITORY
    / "scripts/us/forecasting/vintages/bea_nipa/historical_fingerprints/"
    "fingerprint_historical_releases.py"
)
EXPECTED_LATER_ERA_PARSER_SHA256 = (
    "d0a261248d5448a82f9e1b729c1cb65ca6e2ae64ff4095405d3dc5fcb7dc351e"
)


def sha256_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_raw(spec: ERA.WorkbookSpec) -> bytes:
    return (BUNDLE / "objects" / spec.object_name).read_bytes()


def rewrite_zip(
    data: bytes,
    replacements: Optional[Dict[str, bytes]] = None,
    addition: Optional[Tuple[str, bytes]] = None,
    duplicate_name: Optional[str] = None,
) -> bytes:
    replacements = replacements or {}
    source = zipfile.ZipFile(io.BytesIO(data), "r")
    duplicate_payload = (
        source.read(duplicate_name) if duplicate_name is not None else None
    )
    output_buffer = io.BytesIO()
    with source, zipfile.ZipFile(output_buffer, "w") as output:
        for info in source.infolist():
            payload = replacements.get(info.filename, source.read(info.filename))
            output.writestr(info, payload)
        if addition is not None:
            output.writestr(addition[0], addition[1])
        if duplicate_name is not None:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                output.writestr(duplicate_name, duplicate_payload)
    return output_buffer.getvalue()


def workbook_sheet_path(data: bytes, sheet_name: str) -> str:
    with zipfile.ZipFile(io.BytesIO(data), "r") as archive:
        members, _manifest = ERA.validate_zip_members(archive)
        relationships, _count, _digest = ERA.validate_relationships(archive, members)
        return dict(ERA.workbook_sheets(archive, relationships))[sheet_name]


def mutate_cell_xml(
    data: bytes,
    sheet_name: str,
    address: str,
    mutation: Callable[[ET.Element, ET.Element], None],
) -> bytes:
    sheet_path = workbook_sheet_path(data, sheet_name)
    with zipfile.ZipFile(io.BytesIO(data), "r") as archive:
        root = ET.fromstring(archive.read(sheet_path))
    cell = root.find(".//m:c[@r='%s']" % address, ERA.NS)
    if cell is None:
        raise AssertionError("fixture cell is absent: %s" % address)
    mutation(root, cell)
    replacement = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    return rewrite_zip(data, {sheet_path: replacement})


def mutate_row_number(data: bytes, sheet_name: str, old: str, new: str) -> bytes:
    sheet_path = workbook_sheet_path(data, sheet_name)
    with zipfile.ZipFile(io.BytesIO(data), "r") as archive:
        root = ET.fromstring(archive.read(sheet_path))
    row = root.find(".//m:row[@r='%s']" % old, ERA.NS)
    if row is None:
        raise AssertionError("fixture row is absent")
    row.set("r", new)
    replacement = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    return rewrite_zip(data, {sheet_path: replacement})


def mutate_shared_string_for_cell(
    data: bytes,
    sheet_name: str,
    address: str,
    new_text: str,
) -> bytes:
    sheet_path = workbook_sheet_path(data, sheet_name)
    with zipfile.ZipFile(io.BytesIO(data), "r") as archive:
        sheet = ET.fromstring(archive.read(sheet_path))
        cell = sheet.find(".//m:c[@r='%s']" % address, ERA.NS)
        if cell is None:
            raise AssertionError("fixture cell is absent")
        value = cell.find("m:v", ERA.NS)
        if value is None or value.text is None:
            raise AssertionError("fixture shared-string index is absent")
        index = int(value.text)
        strings = ET.fromstring(archive.read("xl/sharedStrings.xml"))
    item = list(strings)[index]
    text = item.find("m:t", ERA.NS)
    if text is None:
        raise AssertionError("fixture shared string has no text node")
    text.text = new_text
    replacement = ET.tostring(strings, encoding="utf-8", xml_declaration=True)
    return rewrite_zip(data, {"xl/sharedStrings.xml": replacement})


def mutate_relationship_target(data: bytes) -> bytes:
    path = "xl/_rels/workbook.xml.rels"
    with zipfile.ZipFile(io.BytesIO(data), "r") as archive:
        root = ET.fromstring(archive.read(path))
    node = next(
        item
        for item in list(root)
        if item.attrib.get("Type") == "%s/styles" % ERA.OFFICE_REL_NS
    )
    node.set("Target", "../../escape.xml")
    replacement = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    return rewrite_zip(data, {path: replacement})


def corrupt_compressed_member(data: bytes, member_name: str) -> bytes:
    with zipfile.ZipFile(io.BytesIO(data), "r") as archive:
        info = archive.getinfo(member_name)
        if info.compress_size < 8:
            raise AssertionError("fixture member is too small to corrupt")
        offset = info.header_offset
    name_length = int.from_bytes(data[offset + 26 : offset + 28], "little")
    extra_length = int.from_bytes(data[offset + 28 : offset + 30], "little")
    payload_start = offset + 30 + name_length + extra_length
    mutation_offset = payload_start + info.compress_size // 2
    mutated = bytearray(data)
    mutated[mutation_offset] ^= 1
    return bytes(mutated)


def parse_mutated(data: bytes, spec: ERA.WorkbookSpec):
    return ERA._parse_workbook_bytes(
        data,
        spec,
        enforce_pinned_manifests=False,
    )


class ProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not BUNDLE.is_dir():
            raise AssertionError("the exact preserved sequence-25 bundle is required")
        cls.section1 = ERA.WORKBOOK_BY_SECTION["1"]
        cls.section2 = ERA.WORKBOOK_BY_SECTION["2"]
        cls.section1_bytes = read_raw(cls.section1)
        cls.section2_bytes = read_raw(cls.section2)
        cls.artifact = ERA.build_artifact(BUNDLE)

    def assert_profile_error(self, callable_object, pattern: str) -> None:
        with self.assertRaisesRegex(ERA.ProfileError, pattern):
            callable_object()

    def test_exact_profile_and_isolation_from_later_parser(self) -> None:
        self.assertEqual(ERA.profile_sha256(), ERA.EXPECTED_PROFILE_SHA256)
        self.assertEqual(ERA.expected_pair_sha256(), ERA.PAIR_HASH)
        self.assertEqual(
            sha256_file(LATER_ERA_PARSER), EXPECTED_LATER_ERA_PARSER_SHA256
        )
        source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertNotIn("fingerprint_historical_releases", source)
        self.assertEqual(ERA.GROUPED_INTEGER_PATTERN.flags & 256, 256)
        self.assertEqual(ERA.INDEX_DECIMAL_PATTERN.flags & 256, 256)

    def test_python_sources_pass_closed_style_and_syntax_checks(self) -> None:
        for path in (MODULE_PATH, pathlib.Path(__file__).resolve()):
            source = path.read_text(encoding="utf-8")
            ast.parse(source, filename=str(path))
            compile(source, str(path), "exec", dont_inherit=True)
            self.assertTrue(source.endswith("\n"))
            for number, line in enumerate(source.splitlines(), start=1):
                self.assertNotIn("\t", line, "%s:%d contains a tab" % (path, number))
                self.assertEqual(
                    line,
                    line.rstrip(),
                    "%s:%d has trailing whitespace" % (path, number),
                )
                self.assertLessEqual(
                    len(line),
                    99,
                    "%s:%d exceeds 99 columns" % (path, number),
                )

    def test_exact_bundle_and_artifact_boundaries(self) -> None:
        artifact = self.artifact
        self.assertEqual(artifact["capture"]["raw_pair_sha256"], ERA.PAIR_HASH)
        self.assertEqual(
            artifact["capture"]["receipt_semantic_sha256"],
            ERA.RECEIPT_SEMANTIC_SHA256,
        )
        self.assertEqual(
            artifact["capture"]["receipt_file_sha256"], ERA.RECEIPT_FILE_SHA256
        )
        self.assertTrue(artifact["capture"]["present_day_retrieval_only"])
        self.assertFalse(artifact["capture"]["network_transport_verified"])
        release = artifact["release"]
        self.assertTrue(release["section2_embedded_creation_is_post_release"])
        self.assertTrue(release["section2_http_last_modified_is_post_release"])
        self.assertFalse(release["release_event_is_workbook_snapshot"])
        self.assertIn("CANNOT_PROVE", release["section2_temporal_blocker"])
        encoded = ERA.canonical_json_bytes(artifact).decode("utf-8")
        self.assertNotIn(str(BUNDLE), encoded)

    def test_all_gates_are_false_at_every_emitted_scope(self) -> None:
        expected = ERA.false_gates()

        def visit(value):
            if isinstance(value, dict):
                if "gates" in value:
                    self.assertEqual(value["gates"], expected)
                    self.assertFalse(any(value["gates"].values()))
                for child in value.values():
                    visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)

        visit(self.artifact)

    def test_exact_histories_missingness_and_terminal_reconstruction(self) -> None:
        targets = {item["target_id"]: item for item in self.artifact["targets"]}
        self.assertEqual(set(targets), set(ERA.TARGET_BY_ID))
        for target_id, target in targets.items():
            self.assertEqual(target["reference_period_count"], 283)
            self.assertEqual(len(target["observations"]), 283)
            self.assertEqual(target["previous_quarter"]["period"], "2017Q2")
            self.assertEqual(target["current_quarter"]["period"], "2017Q3")
            spec = ERA.TARGET_BY_ID[target_id]
            self.assertEqual(
                target["previous_quarter"]["source_display_text"], spec.previous_display
            )
            self.assertEqual(
                target["current_quarter"]["source_display_text"], spec.current_display
            )
            self.assertEqual(target["history_display_sha256"], spec.history_sha256)
        core = targets["core_pce_price_index"]
        self.assertEqual(core["source_missing_count"], 48)
        self.assertEqual(core["observed_value_count"], 235)
        self.assertTrue(
            all(
                item["source_state"] == "SOURCE_MISSING"
                and item["source_display_text"] == "....."
                and item["canonical_number"] is None
                for item in core["observations"][:48]
            )
        )
        self.assertEqual(core["observations"][48]["period"], "1959Q1")
        self.assertTrue(
            all(item["source_state"] == "OBSERVED" for item in core["observations"][48:])
        )
        for target_id in set(targets) - {"core_pce_price_index"}:
            self.assertEqual(targets[target_id]["source_missing_count"], 0)

    def test_exact_rational_annualization_and_release_checks(self) -> None:
        targets = {item["target_id"]: item for item in self.artifact["targets"]}
        expected = {
            "nominal_gdp": ("5.199003469740", "5.2"),
            "real_gdp": ("2.988959770143", "3.0"),
            "gdp_deflator": ("2.143911696681", "2.1"),
            "pce_price_index": ("1.504770117366", "1.5"),
            "core_pce_price_index": ("1.317974607757", "1.3"),
        }
        for target_id, (decimal, statement) in expected.items():
            record = targets[target_id]["annualized_percent_change"]
            self.assertEqual(record["rounded_decimal_12dp"], decimal)
            self.assertEqual(record["rounded_release_statement_1dp"], statement)
            numerator = int(record["exact_ratio_numerator"])
            denominator = int(record["exact_ratio_denominator"])
            self.assertEqual(math.gcd(abs(numerator), denominator), 1)
        checks = self.artifact["semantic_cross_checks"]
        self.assertFalse(checks["origin_evidence"])
        self.assertEqual(
            checks["nominal_gdp_release_level"][
                "computed_billions_of_dollars_1dp"
            ],
            "19,495.5",
        )
        self.assertTrue(checks["nominal_gdp_release_level"]["matches"])
        self.assertFalse(checks["nominal_gdp_release_level"]["origin_evidence"])
        self.assertEqual(
            checks["workbook_terminal_display_values"],
            {
                target.target_id: target.current_display
                for target in ERA.TARGET_SPECS
            },
        )
        self.assertEqual(
            set(checks["rounded_release_statements"]),
            {"real_gdp", "pce_price_index", "core_pce_price_index"},
        )
        self.assertTrue(
            all(
                item["matches"] and not item["origin_evidence"]
                for item in checks["rounded_release_statements"].values()
            )
        )

    def test_closed_numeric_lexical_grammars(self) -> None:
        level = ERA.TARGET_BY_ID["nominal_gdp"]
        index = ERA.TARGET_BY_ID["gdp_deflator"]
        self.assertEqual(
            ERA.parse_canonical_number("19,495,476", level, "X"),
            {"canonical_decimal": "19495476", "coefficient": "19495476", "scale": "0"},
        )
        self.assertEqual(
            ERA.parse_canonical_number("113.630", index, "X"),
            {"canonical_decimal": "113.630", "coefficient": "113630", "scale": "3"},
        )
        rejected_levels = (
            "19495476",
            "19,49,476",
            "019,495,476",
            "+19,495,476",
            "-19,495,476",
            "19,495,476 ",
            "19.495.476",
            "１９,４９５,４７６",
            "1e6",
            ".....",
        )
        rejected_indices = (
            "113.63",
            "113.6300",
            "0113.630",
            "+113.630",
            "-113.630",
            "113.630 ",
            "113,630",
            ".630",
            "1.13630e2",
            "NaN",
            "Inf",
            "１１３.６３０",
            ".....",
        )
        for value in rejected_levels:
            self.assert_profile_error(
                lambda value=value: ERA.parse_canonical_number(value, level, "X"),
                "grouped positive integer",
            )
        for value in rejected_indices:
            self.assert_profile_error(
                lambda value=value: ERA.parse_canonical_number(value, index, "X"),
                "positive 3-decimal index",
            )

    def test_cell_type_mutation_fails(self) -> None:
        mutated = mutate_cell_xml(
            self.section1_bytes,
            "T10105-Q",
            "JZ9",
            lambda _root, cell: cell.set("t", "n"),
        )
        self.assert_profile_error(
            lambda: parse_mutated(mutated, self.section1), "type/style/formula"
        )

    def test_cell_style_and_style_definition_mutations_fail(self) -> None:
        mutated_cell = mutate_cell_xml(
            self.section1_bytes,
            "T10105-Q",
            "JZ9",
            lambda _root, cell: cell.set("s", "0"),
        )
        self.assert_profile_error(
            lambda: parse_mutated(mutated_cell, self.section1), "type/style/formula"
        )
        with zipfile.ZipFile(io.BytesIO(self.section1_bytes), "r") as archive:
            styles = ET.fromstring(archive.read("xl/styles.xml"))
        second = styles.find("m:cellXfs", ERA.NS)[1]
        second.set("numFmtId", "3")
        mutated_style = rewrite_zip(
            self.section1_bytes,
            {
                "xl/styles.xml": ET.tostring(
                    styles, encoding="utf-8", xml_declaration=True
                )
            },
        )
        self.assert_profile_error(
            lambda: parse_mutated(mutated_style, self.section1), "style 1"
        )

    def test_grouping_and_decimal_xml_mutations_fail(self) -> None:
        bad_grouping = mutate_shared_string_for_cell(
            self.section1_bytes, "T10105-Q", "JZ9", "19,49,476"
        )
        self.assert_profile_error(
            lambda: parse_mutated(bad_grouping, self.section1),
            "grouped positive integer",
        )
        bad_decimal = mutate_shared_string_for_cell(
            self.section1_bytes, "T10109-Q", "JZ9", "113.63"
        )
        self.assert_profile_error(
            lambda: parse_mutated(bad_decimal, self.section1),
            "positive 3-decimal index",
        )

    def test_shared_string_index_mutations_fail(self) -> None:
        out_of_range = mutate_cell_xml(
            self.section1_bytes,
            "T10105-Q",
            "JZ9",
            lambda _root, cell: cell.find("m:v", ERA.NS).__setattr__(
                "text", "999999999"
            ),
        )
        self.assert_profile_error(
            lambda: parse_mutated(out_of_range, self.section1), "out of range"
        )
        leading_zero = mutate_cell_xml(
            self.section1_bytes,
            "T10105-Q",
            "JZ9",
            lambda _root, cell: cell.find("m:v", ERA.NS).__setattr__("text", "01"),
        )
        self.assert_profile_error(
            lambda: parse_mutated(leading_zero, self.section1),
            "canonical unsigned integer",
        )

    def test_formula_mutation_fails(self) -> None:
        def add_formula(_root, cell):
            formula = ET.Element("{%s}f" % ERA.MAIN_NS)
            formula.text = "1+1"
            cell.insert(0, formula)

        mutated = mutate_cell_xml(
            self.section1_bytes, "T10105-Q", "JZ9", add_formula
        )
        self.assert_profile_error(
            lambda: parse_mutated(mutated, self.section1), "contains a formula"
        )

    def test_duplicate_and_unsafe_zip_member_mutations_fail(self) -> None:
        duplicate = rewrite_zip(
            self.section2_bytes, duplicate_name="xl/workbook.xml"
        )
        self.assert_profile_error(
            lambda: parse_mutated(duplicate, self.section2), "alias or duplicate"
        )
        unsafe = rewrite_zip(
            self.section2_bytes, addition=("../escape.xml", b"unsafe")
        )
        self.assert_profile_error(
            lambda: parse_mutated(unsafe, self.section2), "path is unsafe"
        )

    def test_corrupt_zip_member_crc_fails_closed(self) -> None:
        corrupted = corrupt_compressed_member(
            self.section2_bytes, "docProps/app.xml"
        )
        self.assert_profile_error(
            lambda: parse_mutated(corrupted, self.section2),
            "CRC/decompression|corrupt ZIP member",
        )

    def test_relationship_traversal_mutation_fails(self) -> None:
        mutated = mutate_relationship_target(self.section2_bytes)
        self.assert_profile_error(
            lambda: parse_mutated(mutated, self.section2), "escapes the package"
        )

    def test_row_code_and_axis_mutations_fail(self) -> None:
        row = mutate_row_number(self.section1_bytes, "T10105-Q", "9", "10")
        self.assert_profile_error(
            lambda: parse_mutated(row, self.section1), "invalid cell address"
        )
        code = mutate_shared_string_for_cell(
            self.section1_bytes, "T10105-Q", "C9", "A191XX"
        )
        self.assert_profile_error(
            lambda: parse_mutated(code, self.section1), "mapping/header drifted"
        )
        axis = mutate_shared_string_for_cell(
            self.section1_bytes, "T10105-Q", "JZ8", "2017Q4"
        )
        self.assert_profile_error(
            lambda: parse_mutated(axis, self.section1), "period axis drifted"
        )

    def test_incomplete_history_and_unknown_missing_tokens_fail(self) -> None:
        incomplete = mutate_shared_string_for_cell(
            self.section2_bytes, "T20304-Q", "JX34", "....."
        )
        self.assert_profile_error(
            lambda: parse_mutated(incomplete, self.section2),
            "numeric history is incomplete",
        )
        for token in ("....", "", "NA"):
            mutated = mutate_shared_string_for_cell(
                self.section2_bytes, "T20304-Q", "D34", token
            )
            self.assert_profile_error(
                lambda mutated=mutated: parse_mutated(mutated, self.section2),
                "pre-history state drifted",
            )

    def test_raw_hash_and_receipt_mutations_fail_before_parsing(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="hmi7-era2017-mutated-", dir="/private/tmp"
        ) as temporary:
            root = pathlib.Path(temporary)
            copied = root / ERA.BUNDLE_NAME
            shutil.copytree(BUNDLE, copied)
            raw = copied / "objects" / self.section1.object_name
            raw.chmod(0o600)
            with raw.open("r+b") as stream:
                stream.seek(-1, os.SEEK_END)
                original = stream.read(1)
                stream.seek(-1, os.SEEK_END)
                stream.write(bytes([original[0] ^ 1]))
            self.assert_profile_error(
                lambda: ERA.build_artifact(copied), "exact identity drifted"
            )
        with tempfile.TemporaryDirectory(
            prefix="hmi7-era2017-receipt-", dir="/private/tmp"
        ) as temporary:
            root = pathlib.Path(temporary)
            copied = root / ERA.BUNDLE_NAME
            shutil.copytree(BUNDLE, copied)
            receipt = copied / ERA.RECEIPT_NAME
            receipt.chmod(0o600)
            with receipt.open("r+b") as stream:
                stream.seek(-2, os.SEEK_END)
                original = stream.read(1)
                stream.seek(-2, os.SEEK_END)
                stream.write(bytes([original[0] ^ 1]))
            self.assert_profile_error(
                lambda: ERA.build_artifact(copied), "exact identity drifted"
            )

    def test_symlink_hardlink_and_extra_file_bundle_mutations_fail(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="hmi7-era2017-links-", dir="/private/tmp"
        ) as temporary:
            root = pathlib.Path(temporary)
            copied = root / ERA.BUNDLE_NAME
            shutil.copytree(BUNDLE, copied)
            raw = copied / "objects" / self.section1.object_name
            os.link(raw, root / "raw-hardlink.xlsx")
            self.assert_profile_error(
                lambda: ERA.validate_bundle(copied), "single-link regular file"
            )
        with tempfile.TemporaryDirectory(
            prefix="hmi7-era2017-symlink-", dir="/private/tmp"
        ) as temporary:
            root = pathlib.Path(temporary)
            copied = root / ERA.BUNDLE_NAME
            shutil.copytree(BUNDLE, copied)
            (copied / "objects").chmod(0o700)
            raw = copied / "objects" / self.section1.object_name
            target = root / "raw-target.xlsx"
            raw.rename(target)
            raw.symlink_to(target)
            self.assert_profile_error(
                lambda: ERA.validate_bundle(copied), "path is unsafe"
            )
        with tempfile.TemporaryDirectory(
            prefix="hmi7-era2017-extra-", dir="/private/tmp"
        ) as temporary:
            root = pathlib.Path(temporary)
            copied = root / ERA.BUNDLE_NAME
            shutil.copytree(BUNDLE, copied)
            copied.chmod(0o700)
            (copied / "unexpected").write_bytes(b"x")
            self.assert_profile_error(
                lambda: ERA.validate_bundle(copied), "root file set drifted"
            )

    def test_cli_is_cwd_independent_and_byte_deterministic(self) -> None:
        digests = []
        with tempfile.TemporaryDirectory(
            prefix="hmi7-era2017-cli-", dir="/private/tmp"
        ) as temporary:
            temp = pathlib.Path(temporary)
            for index, cwd in enumerate((REPOSITORY, temp)):
                output = temp / ("output-%d" % index)
                result = subprocess.run(
                    [
                        sys.executable,
                        str(MODULE_PATH),
                        "--bundle",
                        str(BUNDLE),
                        "--output-dir",
                        str(output),
                    ],
                    cwd=str(cwd),
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                digest_line = next(
                    line for line in result.stdout.splitlines() if line.startswith("sha256=")
                )
                digest = digest_line.split("=", 1)[1]
                artifact = next(output.glob("*.json"))
                self.assertEqual(sha256_file(artifact), digest)
                self.assertEqual(
                    artifact.read_bytes(), ERA.canonical_json_bytes(json_load(artifact))
                )
                digests.append(digest)
        self.assertEqual(len(set(digests)), 1)


def json_load(path: pathlib.Path):
    import json

    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


if __name__ == "__main__":
    unittest.main(verbosity=2)
