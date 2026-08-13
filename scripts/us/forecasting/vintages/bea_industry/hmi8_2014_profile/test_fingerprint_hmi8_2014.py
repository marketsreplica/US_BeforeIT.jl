#!/usr/bin/env python3
"""Adversarial tests for the isolated BEA HMI8 January-2014 profile."""

from __future__ import annotations

import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from dataclasses import replace
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE = HERE / "fingerprint_hmi8_2014.py"
sys.path.insert(0, str(HERE))
import fingerprint_hmi8_2014 as hmi8  # noqa: E402


CAPTURE_DIR = Path(
    os.environ.get("BEA_HMI8_2014_CAPTURE_DIR", "/tmp/bea-hmi8-20140123.NDC4Vc")
)
WORKBOOK_DIR = Path(
    os.environ.get(
        "BEA_HMI8_2014_WORKBOOK_DIR", "/tmp/bea-hmi8-sheet-inspect.yjRVD3"
    )
)
EXACT_INPUTS_PRESENT = all(
    (CAPTURE_DIR / spec.name).is_file() for spec in hmi8.CAPTURE_SPECS
) and all((WORKBOOK_DIR / spec.filename).is_file() for spec in hmi8.WORKBOOK_SPECS)


def make_zip(entries: list[tuple[str, bytes]]) -> bytes:
    buffer = io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(buffer, "w", zipfile.ZIP_STORED) as archive:
            for name, payload in entries:
                archive.writestr(name, payload)
    return buffer.getvalue()


def rewrite_member(data: bytes, name: str, transform) -> bytes:
    source = zipfile.ZipFile(io.BytesIO(data))
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as target:
        found = False
        for info in source.infolist():
            payload = source.read(info)
            if info.filename == name:
                payload = transform(payload)
                found = True
            target.writestr(info.filename, payload, compress_type=info.compress_type)
    source.close()
    if not found:
        raise AssertionError("member not found: %s" % name)
    return buffer.getvalue()


def replace_once(data: bytes, old: bytes, new: bytes) -> bytes:
    if data.count(old) != 1:
        raise AssertionError("expected exactly one mutation target")
    return data.replace(old, new, 1)


@unittest.skipUnless(EXACT_INPUTS_PRESENT, "pinned HMI8 temporary inputs unavailable")
class ExactProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.artifact = hmi8.build_artifact(CAPTURE_DIR, WORKBOOK_DIR)

    def test_frozen_profile_and_artifact_hashes(self) -> None:
        self.assertEqual(
            hmi8.profile_contract_sha256(), hmi8.EXPECTED_PROFILE_CONTRACT_SHA256
        )
        self.assertEqual(
            self.artifact["artifact_sha256"], hmi8.EXPECTED_ARTIFACT_SHA256
        )
        self.assertTrue(all(not value for value in self.artifact["gates"].values()))

    def test_evidence_is_nonadmitting_and_post_release(self) -> None:
        evidence = self.artifact["evidence_classification"]
        self.assertEqual(
            evidence["byte_observation_mode"], "PRESENT_DAY_ARCHIVE_RETRIEVAL"
        )
        self.assertEqual(evidence["availability_precision"], "DATE_ONLY")
        self.assertEqual(
            evidence["availability_ceiling"], "2014-01-23T23:59:59.999999-05:00"
        )
        self.assertIn(
            "2015-03-25",
            " ".join(evidence["official_archive_http_last_modified"].values()),
        )
        self.assertIn(
            "NOT_EMBEDDED",
            evidence["http_last_modified_evidence_status"],
        )
        self.assertFalse(
            self.artifact["mapping_decision"]["detail_supports_HS_ORE_split"]
        )
        self.assertFalse(self.artifact["mapping_decision"]["ABM_state_emitted"])

    def test_complete_axes_and_explicit_special_accounts(self) -> None:
        reports = self.artifact["workbooks"]
        for key in ("summary_make", "summary_use"):
            logical = reports[key]["structure"]["logical_profile"]
            self.assertEqual(logical["years"], list(hmi8.YEAR_SHEETS))
            self.assertTrue(logical["annual_axis_complete"])
            self.assertEqual(logical["ordinary_axis_count"], 69)
        for key in ("detail_make", "detail_use"):
            logical = reports[key]["structure"]["logical_profile"]
            self.assertEqual(logical["row_axis_count"], 388)
            self.assertEqual(logical["column_axis_count"], 388)
            self.assertEqual(logical["single_combined_real_estate_code"], "531000")
            self.assertEqual(
                logical["crosswalk"]["used_components"], ["S00401", "S00402"]
            )
            self.assertEqual(
                logical["crosswalk"]["other_components"], ["S00300", "S00900"]
            )

    def test_formula_exception_is_exact_and_outside_logical_range(self) -> None:
        structures = {
            key: value["structure"] for key, value in self.artifact["workbooks"].items()
        }
        for key in ("summary_make", "summary_use", "detail_make"):
            self.assertEqual(structures[key]["formula_exception"], [])
        formulas = structures["detail_use"]["formula_exception"]
        self.assertEqual(
            [item["cell"] for item in formulas],
            ["OP%d" % n for n in range(337, 345)],
        )
        self.assertTrue(
            structures["detail_use"]["formula_exception_outside_logical_range"]
        )
        self.assertGreater(hmi8.column_number("OP"), hmi8.column_number("ON"))

    def test_accounting_is_a_rounded_source_check_not_rebalancing(self) -> None:
        accounting = self.artifact["accounting"]
        self.assertEqual(
            accounting["observed_maximum_absolute_residuals"],
            {
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
            },
        )
        self.assertFalse(accounting["published_rounding_rebalance_applied"])
        self.assertEqual(
            accounting["special_component_checks_2007"]["Used"]["summary_output"],
            10_036,
        )
        self.assertEqual(
            accounting["special_component_checks_2007"]["Other"]["summary_output"],
            1_071,
        )
        self.assertFalse(
            accounting["real_estate_check_2007"]["HS_ORE_split_identified"]
        )

    def test_root_and_unrelated_cwd_cli_are_identical(self) -> None:
        command = [
            sys.executable,
            str(MODULE),
            "--capture-dir",
            str(CAPTURE_DIR),
            "--workbook-dir",
            str(WORKBOOK_DIR),
        ]
        repository_root = HERE.parents[5]
        root_run = subprocess.run(
            command,
            cwd=repository_root,
            check=True,
            capture_output=True,
        )
        with tempfile.TemporaryDirectory() as directory:
            unrelated_run = subprocess.run(
                command,
                cwd=directory,
                check=True,
                capture_output=True,
            )
        self.assertEqual(root_run.stderr, b"")
        self.assertEqual(root_run.stdout, unrelated_run.stdout)
        self.assertEqual(root_run.stdout, hmi8.canonical_json_bytes(self.artifact))

    def test_pinned_hash_and_hardlink_fail_closed(self) -> None:
        spec = hmi8.CAPTURE_SPECS[0]
        with tempfile.TemporaryDirectory() as directory:
            source = CAPTURE_DIR / spec.name
            mutated = Path(directory) / spec.name
            mutated.write_bytes(source.read_bytes() + b"\n")
            with self.assertRaisesRegex(hmi8.ProfileError, "pinned identity mismatch"):
                hmi8._read_regular_file(mutated, spec)
            first = Path(directory) / "first"
            second = Path(directory) / "second"
            shutil.copyfile(source, first)
            os.link(first, second)
            with self.assertRaisesRegex(hmi8.ProfileError, "hard-linked"):
                hmi8._read_regular_file(second, spec)

    def test_shared_string_style_formula_and_axis_mutations_fail(self) -> None:
        summary_spec = next(
            spec for spec in hmi8.WORKBOOK_SPECS if spec.key == "summary_make"
        )
        detail_spec = next(
            spec for spec in hmi8.WORKBOOK_SPECS if spec.key == "detail_use"
        )
        summary_data = (WORKBOOK_DIR / summary_spec.filename).read_bytes()
        detail_data = (WORKBOOK_DIR / detail_spec.filename).read_bytes()

        bad_index = rewrite_member(
            summary_data,
            "xl/worksheets/sheet1.xml",
            lambda data: re.sub(
                rb'(<c r="A1"[^>]*><v>)[0-9]+(</v>)',
                rb"\g<1>999999\g<2>",
                data,
                count=1,
            ),
        )
        with self.assertRaisesRegex(hmi8.ProfileError, "shared-string index"):
            hmi8.inspect_workbook(bad_index, summary_spec)

        bad_formula = rewrite_member(
            detail_data,
            "xl/worksheets/sheet3.xml",
            lambda data: replace_once(
                data,
                b"#REF!-SUM(C337:OA337,OC337:OM337)",
                b"#REF!-SUM(C337:OA337,OC337:ON337)",
            ),
        )
        with self.assertRaisesRegex(hmi8.ProfileError, "formula/error set"):
            hmi8.inspect_workbook(bad_formula, detail_spec)

        added_formula = rewrite_member(
            summary_data,
            "xl/worksheets/sheet3.xml",
            lambda data: replace_once(
                data,
                b'<c r="C76" s="16"><v>',
                b'<c r="C76" s="16"><f>1</f><v>',
            ),
        )
        with self.assertRaisesRegex(hmi8.ProfileError, "formula/error set"):
            hmi8.inspect_workbook(added_formula, summary_spec)

        bad_style = rewrite_member(
            detail_data,
            "xl/worksheets/sheet3.xml",
            lambda data: replace_once(
                data,
                b'<c r="OP337" s="11" t="e">',
                b'<c r="OP337" s="9999" t="e">',
            ),
        )
        with self.assertRaisesRegex(hmi8.ProfileError, "style index"):
            hmi8.inspect_workbook(bad_style, detail_spec)

        bad_history = rewrite_member(
            summary_data,
            "xl/workbook.xml",
            lambda data: replace_once(data, b'name="1997"', b'name="199X"'),
        )
        with self.assertRaisesRegex(hmi8.ProfileError, "sheet order/name"):
            hmi8.inspect_workbook(bad_history, summary_spec)

        view = hmi8.inspect_workbook(summary_data, summary_spec)
        old_index = view.sheets["1997"]["A7"].value
        assert old_index is not None
        used_index = view.shared_strings.index("Used")
        bad_code = rewrite_member(
            summary_data,
            "xl/worksheets/sheet3.xml",
            lambda data: re.sub(
                rb'(<c r="A7"[^>]*><v>)' + old_index.encode() + rb"(</v>)",
                rb"\g<1>" + str(used_index).encode() + rb"\g<2>",
                data,
                count=1,
            ),
        )
        bad_view = hmi8.inspect_workbook(bad_code, summary_spec)
        with self.assertRaisesRegex(hmi8.ProfileError, "axis mismatch"):
            hmi8._validate_summary(bad_view)

    def test_metadata_semantic_mutation_fails(self) -> None:
        payloads = {
            spec.name: (CAPTURE_DIR / spec.name).read_bytes()
            for spec in hmi8.CAPTURE_SPECS
            if spec.name.endswith(".json")
        }
        mutated = json.loads(payloads["release-files.json"])
        mutated["FileArray"][1] = mutated["FileArray"][1].replace(
            "AllTablesIO.zip", "AllTablesI0.zip"
        )
        payloads["release-files.json"] = json.dumps(mutated).encode()
        with self.assertRaisesRegex(hmi8.ProfileError, "file-list"):
            hmi8._validate_metadata(payloads)

    def test_accounting_mutation_exceeds_published_rounding_bound(self) -> None:
        views: dict[str, hmi8.WorkbookView] = {}
        for spec in hmi8.WORKBOOK_SPECS:
            views[spec.key] = hmi8.inspect_workbook(
                (WORKBOOK_DIR / spec.filename).read_bytes(), spec
            )
        cell = views["summary_make"].sheets["2012"]["C7"]
        assert cell.value is not None
        views["summary_make"].sheets["2012"]["C7"] = replace(
            cell, value=str(int(cell.value) + 100)
        )
        with self.assertRaisesRegex(hmi8.ProfileError, "accounting bound exceeded"):
            hmi8._accounting_diagnostics(
                views["summary_make"],
                views["summary_use"],
                views["detail_make"],
                views["detail_use"],
            )


class PureAdversarialTests(unittest.TestCase):
    def test_json_duplicate_member_is_rejected_after_decoding(self) -> None:
        with self.assertRaisesRegex(hmi8.ProfileError, "duplicate object member"):
            hmi8.parse_json(b'{"a":1,"\\u0061":2}', "duplicate.json")

    def test_integer_grammar_is_closed_and_arbitrary_precision(self) -> None:
        spec = hmi8.WORKBOOK_SPECS[0]
        huge = "9" * 250
        for token in (
            "+1",
            " 1",
            "1 ",
            "01",
            "-0",
            "1,000",
            "1.0",
            "1e3",
            "1_000",
            "−1",
            "١",
            "",
        ):
            view = hmi8.WorkbookView(
                spec,
                [],
                [3],
                {"x": {"A1": hmi8.Cell("A1", 1, 1, None, 0, token, None)}},
                {},
                {},
            )
            with self.subTest(token=token), self.assertRaisesRegex(
                hmi8.ProfileError, "integer grammar"
            ):
                hmi8._integer(view, "x", 1, 1)
        view = hmi8.WorkbookView(
            spec,
            [],
            [3],
            {"x": {"A1": hmi8.Cell("A1", 1, 1, None, 0, huge, None)}},
            {},
            {},
        )
        value, token = hmi8._integer(view, "x", 1, 1)
        self.assertEqual(token, huge)
        self.assertEqual(value, int(huge))

    def test_zip_duplicate_traversal_case_alias_and_crc_fail(self) -> None:
        for entries in (
            [("a", b"1"), ("a", b"2")],
            [("A", b"1"), ("a", b"2")],
            [("../a", b"1")],
            [("a\\b", b"1")],
        ):
            with self.subTest(entries=entries), self.assertRaises(hmi8.ProfileError):
                hmi8.validate_zip_bytes(make_zip(entries), "synthetic.zip")
        valid = make_zip([("payload", b"UNIQUE_PAYLOAD")])
        corrupted = replace_once(valid, b"UNIQUE_PAYLOAD", b"BROKEN_PAYLOAD")
        with self.assertRaisesRegex(hmi8.ProfileError, "CRC"):
            hmi8.validate_zip_bytes(corrupted, "corrupt.zip")

    def test_relationship_traversal_duplicate_and_missing_target_fail(self) -> None:
        template = (
            '<?xml version="1.0"?><Relationships xmlns="%s">%s</Relationships>'
            % (hmi8.PACKAGE_REL_NS, "%s")
        )
        relation = (
            '<Relationship Id="rId1" Type="%s" Target="%s"/>'
            % (hmi8.OFFICE_REL_NS + "/officeDocument", "%s")
        )
        for target in ("../escape.xml", "missing.xml"):
            xml = (template % (relation % target)).encode()
            with self.subTest(target=target), self.assertRaises(hmi8.ProfileError):
                hmi8.validate_relationships(
                    {"_rels/.rels": xml, "xl/workbook.xml": b"x"}, "synthetic"
                )
        duplicate = (template % ((relation % "xl/workbook.xml") * 2)).encode()
        with self.assertRaisesRegex(hmi8.ProfileError, "duplicate relationship"):
            hmi8.validate_relationships(
                {"_rels/.rels": duplicate, "xl/workbook.xml": b"x"}, "synthetic"
            )

    def test_cell_type_style_shared_index_and_formula_are_closed(self) -> None:
        def worksheet(cell: str) -> bytes:
            return (
                '<worksheet xmlns="%s"><dimension ref="A1"/><sheetData>'
                '<row r="1">%s</row></sheetData></worksheet>' % (hmi8.MAIN_NS, cell)
            ).encode()

        cases = (
            ('<c r="A1" t="inlineStr"/>', "cell type"),
            ('<c r="A1" s="2"><v>1</v></c>', "style index"),
            ('<c r="A1" t="s"><v>1</v></c>', "shared-string index"),
            ('<c r="A1"><f t="array">1</f><v>1</v></c>', "formula attributes"),
        )
        for cell, message in cases:
            with self.subTest(cell=cell), self.assertRaisesRegex(
                hmi8.ProfileError, message
            ):
                hmi8._parse_cells(worksheet(cell), "sheet.xml", ["x"], [3])
        duplicate_row = (
            '<worksheet xmlns="%s"><dimension ref="A1:A2"/><sheetData>'
            '<row r="1"><c r="A1"/></row><row r="1"><c r="A1"/></row>'
            "</sheetData></worksheet>" % hmi8.MAIN_NS
        ).encode()
        with self.assertRaisesRegex(hmi8.ProfileError, "duplicate or unordered"):
            hmi8._parse_cells(duplicate_row, "sheet.xml", ["x"], [3])

    def test_contract_drift_and_false_gates(self) -> None:
        self.assertTrue(all(not value for value in hmi8.false_gates().values()))
        original = hmi8.WORKBOOK_SPECS
        try:
            hmi8.WORKBOOK_SPECS = (
                replace(original[0], expected_structure_sha256="0" * 64),
            ) + original[1:]
            with self.assertRaisesRegex(hmi8.ProfileError, "contract SHA-256 drifted"):
                hmi8._validate_contract()
        finally:
            hmi8.WORKBOOK_SPECS = original


if __name__ == "__main__":
    unittest.main()
