#!/usr/bin/env python3
"""Adversarial tests for the isolated classification physical diagnostic."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import inspect
import io
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import MappingProxyType

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "classification_maps_present_day_physical_profile_v1.py"
SPEC = importlib.util.spec_from_file_location("classification_physical_v1", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load classification physical module")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

PHYSICAL_AUDIT_DIR = Path(
    os.environ.get(
        "CLASSIFICATION_MAPS_PHYSICAL_AUDIT_DIR",
        "/private/tmp/classification-physical-audit.5Yk6GZ",
    )
)
SUMMARY_AUDIT_DIR = Path(
    os.environ.get(
        "CLASSIFICATION_MAPS_SUMMARY_AUDIT_DIR",
        "/private/tmp/special2017-review.cPzpsw/source",
    )
)
EXTERNAL_SOURCE_PATHS = {
    "bea_summary_use_2024": Path(
        SUMMARY_AUDIT_DIR / "IOUse_After_Redefinitions_PRO_Summary.xlsx"
    ),
    "bea_summary_make_2024": Path(
        SUMMARY_AUDIT_DIR / "IOMake_After_Redefinitions_PRO_Summary.xlsx"
    ),
    "bea_industry_commodity_naics_concordance": PHYSICAL_AUDIT_DIR / "bea.xlsx",
    "naics_2017_structure": PHYSICAL_AUDIT_DIR / "naics2017.xlsx",
    "naics_2017_to_2022_concordance": PHYSICAL_AUDIT_DIR / "conc.xlsx",
    "naics_2022_structure": PHYSICAL_AUDIT_DIR / "naics2022.xlsx",
}
EXPECTED_RESULT_BYTE_COUNT = 7_079_600
EXPECTED_RESULT_PHYSICAL_SHA256 = (
    "c39a22dcc2ffe6bd23a93185ddde082c3ee08b79c6ba6eda81fb7ccacc6f0d85"
)
EXPECTED_RESULT_CONTENT_SHA256 = (
    "54b79027ff55717910024b22693540f0aa20580b29dd6b52e9fb4c670600ee0c"
)
EXPECTED_MODULE_SHA256 = (
    "f562825dd5985f889de89597103bc840f4fb27d362054a935951f85882f7bc7a"
)

XML_DECL = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
DOC_REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"


def _fixture_parts(sheet_xml: str | None = None) -> list[tuple[str, bytes]]:
    if sheet_xml is None:
        sheet_xml = (
            XML_DECL
            + f'<worksheet xmlns="{MAIN_NS}"><dimension ref="A1"/>'
            '<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c>'
            "</row></sheetData></worksheet>"
        )
    content_types = (
        XML_DECL
        + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
        "</Types>"
    )
    root_rels = (
        XML_DECL
        + f'<Relationships xmlns="{PKG_REL_NS}">'
        f'<Relationship Id="rId1" Type="{DOC_REL_NS}/officeDocument" Target="xl/workbook.xml"/>'
        "</Relationships>"
    )
    workbook = (
        XML_DECL
        + f'<workbook xmlns="{MAIN_NS}" xmlns:r="{DOC_REL_NS}">'
        '<sheets><sheet name="Synthetic" sheetId="1" r:id="rId1"/></sheets>'
        "</workbook>"
    )
    workbook_rels = (
        XML_DECL
        + f'<Relationships xmlns="{PKG_REL_NS}">'
        f'<Relationship Id="rId1" Type="{DOC_REL_NS}/worksheet" Target="worksheets/sheet1.xml"/>'
        f'<Relationship Id="rId2" Type="{DOC_REL_NS}/styles" Target="styles.xml"/>'
        f'<Relationship Id="rId3" Type="{DOC_REL_NS}/sharedStrings" Target="sharedStrings.xml"/>'
        "</Relationships>"
    )
    styles = (
        XML_DECL
        + f'<styleSheet xmlns="{MAIN_NS}"><cellXfs count="1">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        "</cellXfs></styleSheet>"
    )
    shared = (
        XML_DECL
        + f'<sst xmlns="{MAIN_NS}" count="1" uniqueCount="1"><si><t>x</t></si></sst>'
    )
    return [
        ("[Content_Types].xml", content_types.encode()),
        ("_rels/.rels", root_rels.encode()),
        ("xl/workbook.xml", workbook.encode()),
        ("xl/_rels/workbook.xml.rels", workbook_rels.encode()),
        ("xl/worksheets/sheet1.xml", sheet_xml.encode()),
        ("xl/styles.xml", styles.encode()),
        ("xl/sharedStrings.xml", shared.encode()),
    ]


def _zip_parts(parts: list[tuple[str, bytes]]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, payload in parts:
            archive.writestr(name, payload, compress_type=zipfile.ZIP_DEFLATED)
    return buffer.getvalue()


def _fixture_bytes(sheet_xml: str | None = None) -> bytes:
    return _zip_parts(_fixture_parts(sheet_xml))


def _replace_part(raw: bytes, name: str, transform) -> bytes:
    with zipfile.ZipFile(io.BytesIO(raw), "r") as archive:
        parts = [(info.filename, archive.read(info)) for info in archive.infolist()]
    replaced = []
    for part_name, payload in parts:
        replaced.append((part_name, transform(payload) if part_name == name else payload))
    return _zip_parts(replaced)


def _assert_rejected(test: unittest.TestCase, callback) -> None:
    with test.assertRaises(MODULE.ProfileError):
        callback()


class StrictPrimitiveTests(unittest.TestCase):
    def test_minimal_synthetic_fixture_parses_without_origin_claim(self) -> None:
        workbook = MODULE.parse_workbook_bytes(_fixture_bytes(), "synthetic_fixture")
        self.assertEqual(workbook.raw_byte_count, len(_fixture_bytes()))
        self.assertEqual(tuple(sheet.name for sheet in workbook.sheets), ("Synthetic",))
        self.assertEqual(workbook.sheets[0].cells[0].raw_value, "0")
        self.assertEqual(workbook.sheets[0].cells[0].display, "x")

    def test_formula_error_inline_and_nonfinite_cells_are_rejected(self) -> None:
        base = (
            XML_DECL
            + f'<worksheet xmlns="{MAIN_NS}"><dimension ref="A1"/>'
            '<sheetData><row r="1">{cell}</row></sheetData></worksheet>'
        )
        attacks = (
            '<c r="A1"><f>1+1</f><v>2</v></c>',
            '<c r="A1" t="e"><v>#REF!</v></c>',
            '<c r="A1" t="inlineStr"><is><t>x</t></is></c>',
            '<c r="A1"><v>NaN</v></c>',
            '<c r="A1"><v>Inf</v></c>',
        )
        for attack in attacks:
            with self.subTest(attack=attack):
                _assert_rejected(
                    self,
                    lambda attack=attack: MODULE.parse_workbook_bytes(
                        _fixture_bytes(base.format(cell=attack)), "synthetic_fixture"
                    ),
                )

    def test_xml_encoding_scalar_dtd_entity_pi_and_close_token_attacks(self) -> None:
        valid = _fixture_bytes()
        attacks = (
            b"\xef\xbb\xbf" + _fixture_parts()[4][1],
            '<?xml version="1.0" encoding="UTF-16"?><worksheet/>'.encode("utf-16"),
            (XML_DECL + '<!DOCTYPE worksheet [<!ENTITY x "y">]><worksheet/>').encode(),
            (XML_DECL + '<?attack value?><worksheet/>').encode(),
            (XML_DECL + f'<worksheet xmlns="{MAIN_NS}"><x>]]></x></worksheet>').encode(),
            (XML_DECL + f'<worksheet xmlns="{MAIN_NS}"><x>bad\ufffe</x></worksheet>').encode(),
            (XML_DECL + f'<worksheet xmlns="{MAIN_NS}"><x>&#xFFFE;</x></worksheet>').encode(),
        )
        for attack in attacks:
            with self.subTest(prefix=attack[:30]):
                mutated = _replace_part(valid, "xl/worksheets/sheet1.xml", lambda _: attack)
                _assert_rejected(
                    self,
                    lambda mutated=mutated: MODULE.parse_workbook_bytes(
                        mutated, "synthetic_fixture"
                    ),
                )

    def test_content_type_drives_xml_preflight_even_for_dat_extension(self) -> None:
        parts = _fixture_parts()
        updated: list[tuple[str, bytes]] = []
        for name, payload in parts:
            text = payload.decode()
            if name == "[Content_Types].xml":
                text = text.replace(
                    "</Types>",
                    '<Override PartName="/xl/theme/theme1.dat" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/></Types>',
                )
            if name == "xl/_rels/workbook.xml.rels":
                text = text.replace(
                    "</Relationships>",
                    f'<Relationship Id="rId4" Type="{DOC_REL_NS}/theme" Target="theme/theme1.dat"/></Relationships>',
                )
            updated.append((name, text.encode()))
        updated.append(
            (
                "xl/theme/theme1.dat",
                '<?xml version="1.0" encoding="UTF-16"?><!DOCTYPE a [<!ENTITY x "y">]><a/>'.encode(
                    "utf-16"
                ),
            )
        )
        _assert_rejected(
            self,
            lambda: MODULE.parse_workbook_bytes(
                _zip_parts(updated), "synthetic_fixture"
            ),
        )

    def test_relationship_suffix_requires_exact_relationship_mime(self) -> None:
        raw = _fixture_bytes()
        mutated = _replace_part(
            raw,
            "[Content_Types].xml",
            lambda data: data.replace(
                b"application/vnd.openxmlformats-package.relationships+xml",
                b"application/octet-stream",
            ),
        )
        _assert_rejected(
            self,
            lambda: MODULE.parse_workbook_bytes(mutated, "synthetic_fixture"),
        )

    def test_external_relationship_and_wrong_target_mime_are_rejected(self) -> None:
        raw = _fixture_bytes()
        external = _replace_part(
            raw,
            "_rels/.rels",
            lambda data: data.replace(
                b'Target="xl/workbook.xml"',
                b'Target="xl/workbook.xml" TargetMode="External"',
            ),
        )
        wrong_mime = _replace_part(
            raw,
            "[Content_Types].xml",
            lambda data: data.replace(
                b"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml",
                b"application/xml",
            ),
        )
        for attack in (external, wrong_mime):
            _assert_rejected(
                self,
                lambda attack=attack: MODULE.parse_workbook_bytes(
                    attack, "synthetic_fixture"
                ),
            )

    def test_zip_prefix_suffix_case_duplicate_traversal_and_local_mismatch(self) -> None:
        raw = _fixture_bytes()
        attacks = [b"prefix" + raw, raw + b"suffix"]
        parts = _fixture_parts()
        attacks.append(_zip_parts(parts + [("XL/styles.xml", b"x")]))
        attacks.append(_zip_parts(parts + [("../escape.xml", b"x")]))
        local_mismatch = bytearray(raw)
        name_offset = 30
        local_mismatch[name_offset] = ord("{")
        attacks.append(bytes(local_mismatch))
        for attack in attacks:
            _assert_rejected(
                self,
                lambda attack=attack: MODULE.parse_workbook_bytes(
                    attack, "synthetic_fixture"
                ),
            )

    def test_zip_duplicate_crc_corruption_and_descriptor_flag_are_rejected(self) -> None:
        parts = _fixture_parts()
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, payload in parts:
                archive.writestr(name, payload)
            with self.assertWarns(UserWarning):
                archive.writestr(parts[0][0], parts[0][1])
        duplicate = buffer.getvalue()
        raw = bytearray(_fixture_bytes())
        raw[50] ^= 0x01
        descriptor = bytearray(_fixture_bytes())
        descriptor[6] |= 0x08
        symlink_buffer = io.BytesIO()
        with zipfile.ZipFile(
            symlink_buffer, "w", compression=zipfile.ZIP_DEFLATED
        ) as archive:
            for name, payload in parts:
                info = zipfile.ZipInfo(name)
                info.compress_type = zipfile.ZIP_DEFLATED
                if name == "xl/styles.xml":
                    info.create_system = 3
                    info.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(info, payload)
        for attack in (
            duplicate,
            bytes(raw),
            bytes(descriptor),
            symlink_buffer.getvalue(),
        ):
            _assert_rejected(
                self,
                lambda attack=attack: MODULE.parse_workbook_bytes(
                    attack, "synthetic_fixture"
                ),
            )

    def test_json_duplicate_nonfinite_bom_float_and_alias_types_are_rejected(self) -> None:
        for data in (
            b'{"a":1,"a":2}',
            b'{"a":NaN}',
            b"\xef\xbb\xbf{}",
            b"\xff",
        ):
            _assert_rejected(self, lambda data=data: MODULE.parse_json_bytes(data, "attack"))
        profile = MODULE.load_profile()
        profile["boundary"]["profile_count"] = 6.0
        profile["artifact"]["content_sha256"] = MODULE._profile_semantic_hash(profile)
        _assert_rejected(self, lambda: MODULE.validate_profile_document(profile))
        alias = MappingProxyType(MODULE.load_profile())
        _assert_rejected(self, lambda: MODULE.validate_profile_document(alias))
        tuple_alias = MODULE.load_profile()
        tuple_alias["sources"] = tuple(tuple_alias["sources"])
        _assert_rejected(self, lambda: MODULE.validate_profile_document(tuple_alias))

    def test_profile_self_restamp_cannot_raise_policy_or_change_source(self) -> None:
        for mutation in ("qualified", "source", "profile_id", "extra_key"):
            profile = MODULE.load_profile()
            if mutation == "qualified":
                profile["boundary"]["physically_qualified_profile_count"] = 1
            elif mutation == "source":
                profile["sources"][0]["byte_count"] += 1
            else:
                if mutation == "profile_id":
                    profile["object_profiles"][0]["profile_id"] = "drift"
                else:
                    profile["artifact"]["unexpected"] = "restamped"
            profile["artifact"]["content_sha256"] = MODULE._profile_semantic_hash(profile)
            with self.subTest(mutation=mutation):
                _assert_rejected(
                    self, lambda profile=profile: MODULE.validate_profile_document(profile)
                )

    def test_profile_results_are_detached_and_persistent_policy_is_immutable(self) -> None:
        first = MODULE.load_profile()
        first["sources"][0]["sha256"] = "0" * 64
        second = MODULE.load_profile()
        self.assertNotEqual(first["sources"][0]["sha256"], second["sources"][0]["sha256"])
        mutable_types = (dict, list, set)
        for name, value in vars(MODULE).items():
            if name.isupper():
                self.assertNotIsInstance(value, mutable_types, name)

    def test_public_signatures_have_no_source_verification_bypass(self) -> None:
        self.assertEqual(
            tuple(inspect.signature(MODULE.compile_derivative).parameters),
            ("source_paths",),
        )
        self.assertEqual(
            tuple(inspect.signature(MODULE.validate_derivative_bytes).parameters),
            ("data", "source_paths"),
        )
        _assert_rejected(self, lambda: MODULE.compile_derivative({}))

    def test_symlink_hardlink_and_relative_paths_fail_before_parsing(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as temp:
            root = Path(temp)
            original = root / "body.xlsx"
            original.write_bytes(_fixture_bytes())
            symlink = root / "link.xlsx"
            symlink.symlink_to(original)
            hardlink = root / "hard.xlsx"
            os.link(original, hardlink)
            _assert_rejected(
                self, lambda: MODULE.parse_workbook(symlink, "synthetic_fixture")
            )
            _assert_rejected(
                self, lambda: MODULE.parse_workbook(original, "synthetic_fixture")
            )
            _assert_rejected(
                self,
                lambda: MODULE.parse_workbook(
                    Path("relative.xlsx"), "synthetic_fixture"
                ),
            )


@unittest.skipUnless(
    all(path.is_file() for path in EXTERNAL_SOURCE_PATHS.values()),
    "six exact external diagnostic workbook bodies are unavailable",
)
class ExactObservedBodyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.result = MODULE.compile_derivative(dict(EXTERNAL_SOURCE_PATHS))
        cls.serialized = MODULE.canonical_json_bytes(cls.result)
        cls.by_source = {
            record["source_id"]: record for record in cls.result["sources"]
        }

    def test_ceiling_profile_ids_source_pins_and_no_url_attribution(self) -> None:
        self.assertEqual(len(self.serialized), EXPECTED_RESULT_BYTE_COUNT)
        self.assertEqual(
            hashlib.sha256(self.serialized).hexdigest(),
            EXPECTED_RESULT_PHYSICAL_SHA256,
        )
        self.assertEqual(
            self.result["artifact"]["content_sha256"],
            EXPECTED_RESULT_CONTENT_SHA256,
        )
        self.assertEqual(
            self.result["artifact"]["generator_module_sha256"],
            EXPECTED_MODULE_SHA256,
        )
        self.assertEqual(self.result["artifact"]["status"], "CANNOT_RUN")
        self.assertEqual(self.result["boundary"]["profile_count"], 6)
        self.assertEqual(self.result["boundary"]["physically_qualified_profile_count"], 0)
        self.assertTrue(all(value is False for value in self.result["gates"].values()))
        serialized_text = self.serialized.decode()
        self.assertNotIn('"source_url"', serialized_text)
        self.assertNotIn("bea.gov", serialized_text)
        self.assertNotIn("census.gov", serialized_text)
        self.assertEqual(
            tuple(self.by_source),
            MODULE.SOURCE_IDS,
        )
        for record in self.result["sources"]:
            self.assertTrue(record["body_hash_size_verified"])
            self.assertFalse(record["body_to_url_provenance_verified"])
            self.assertFalse(record["body_to_provider_provenance_verified"])

    def test_summary_axes_and_versioned_successor_mismatch(self) -> None:
        summary = self.result["cross_source_contract"]["summary"]
        self.assertEqual((summary["industry_count"], summary["commodity_count"]), (71, 73))
        self.assertEqual(summary["physical_special_order"], ["Used", "Other"])
        self.assertEqual(summary["accepted_logical_special_order"], ["Other", "Used"])
        self.assertFalse(summary["logical_profile_compatible"])
        self.assertEqual(
            summary["successor_requirement"], "VERSIONED_LOGICAL_SUCCESSOR_REQUIRED"
        )
        self.assertEqual(
            summary["industry_pair_sha256"],
            "6f53fca11a762278d5cfe0f7a9672ebaaffc2afc2751ec5577905984a4077c4d",
        )
        self.assertEqual(
            summary["use_commodity_axis"][-2]["title"],
            "Scrap, used and secondhand goods",
        )
        self.assertEqual(
            summary["make_commodity_axis"][-2]["title"],
            "Scrap, used and secondhand goods /1/",
        )

    def test_bea_phantom_column_hierarchy_special_rows_and_defined_ref_names(self) -> None:
        record = self.by_source["bea_industry_commodity_naics_concordance"]
        diagnostic = record["diagnostic"]
        self.assertEqual(diagnostic["data_row_count"], 499)
        self.assertEqual(diagnostic["hierarchy_unique_counts"], [23, 73, 141, 406, 418])
        self.assertEqual(diagnostic["phantom_column"]["explicit_cell_count"], 500)
        self.assertEqual(diagnostic["phantom_column"]["shared_string_index"], 1152)
        self.assertEqual(diagnostic["phantom_column"]["decoded_value"], "")
        self.assertEqual(diagnostic["special_row_order"], ["Used", "Used", "Other", "Other"])
        self.assertFalse(diagnostic["explicit_industry_vs_commodity_row_axis_available"])
        mismatch = diagnostic["ordinary_title_trailing_space_mismatches"]
        self.assertEqual([(item["code"], item["trailing_space_count"]) for item in mismatch], [("481", 2), ("482", 1), ("485", 1)])
        texts = [item["text"] for item in record["defined_names"]]
        self.assertEqual(texts.count("#REF!"), 3)
        self.assertIn("'NAICS Codes'!#REF!", texts)

    def test_naics_rows_separators_range_codes_direction_and_cardinality(self) -> None:
        naics17 = self.by_source["naics_2017_structure"]["diagnostic"]
        naics22 = self.by_source["naics_2022_structure"]["diagnostic"]
        concordance = self.by_source["naics_2017_to_2022_concordance"]["diagnostic"]
        self.assertEqual((naics17["semantic_row_count"], naics17["separator_row_count"]), (2196, 19))
        self.assertEqual((naics22["semantic_row_count"], naics22["separator_row_count"]), (2125, 19))
        self.assertEqual(concordance["direction"], "NAICS_2017_TO_NAICS_2022")
        self.assertFalse(concordance["reverse_concordance_in_place"])
        self.assertEqual(
            concordance["cardinality_row_counts"],
            {"one_to_one": 928, "one_to_many": 5, "many_to_one": 120, "many_to_many": 97},
        )
        self.assertEqual(len(concordance["space_valued_cells"]), 19)
        self.assertEqual(len(concordance["styled_blank_cells"]), 8)
        self.assertEqual(concordance["space_valued_cells"][4]["display"], "  ")

    def test_every_package_preserves_full_ordered_metadata_and_zero_cell_formulas(self) -> None:
        expected_member_counts = {
            "bea_summary_use_2024": 37,
            "bea_summary_make_2024": 37,
            "bea_industry_commodity_naics_concordance": 12,
            "naics_2017_structure": 14,
            "naics_2017_to_2022_concordance": 12,
            "naics_2022_structure": 13,
        }
        for source_id, expected_count in expected_member_counts.items():
            record = self.by_source[source_id]
            self.assertEqual(len(record["zip_members"]), expected_count)
            self.assertTrue(record["zero_cell_formulas_verified"])
            self.assertTrue(record["zero_error_cells_verified"])
            self.assertTrue(
                record["defined_name_ref_errors_preserved_not_executed"]
            )
            self.assertTrue(all(member["compression_method"] == 8 for member in record["zip_members"]))
            self.assertTrue(all(member["flags"] == 6 for member in record["zip_members"]))

    def test_strict_result_types_and_self_restamps_do_not_bypass_ceiling(self) -> None:
        float_attack = copy.deepcopy(self.result)
        float_attack["boundary"]["profile_count"] = 6.0
        float_attack["artifact"]["content_sha256"] = MODULE._result_semantic_sha256(float_attack)
        _assert_rejected(self, lambda: MODULE.validate_derivative_shape(float_attack))
        tuple_attack = copy.deepcopy(self.result)
        tuple_attack["sources"] = tuple(tuple_attack["sources"])
        _assert_rejected(self, lambda: MODULE.validate_derivative_shape(tuple_attack))
        direction_attack = copy.deepcopy(self.result)
        direction_attack["cross_source_contract"]["naics_concordance_direction"] = "NAICS_2022_TO_NAICS_2017"
        direction_attack["artifact"]["content_sha256"] = MODULE._result_semantic_sha256(direction_attack)
        _assert_rejected(self, lambda: MODULE.validate_derivative_shape(direction_attack))
        qualification_attack = copy.deepcopy(self.result)
        qualification_attack["boundary"]["physically_qualified_profile_count"] = 1
        qualification_attack["artifact"]["content_sha256"] = MODULE._result_semantic_sha256(qualification_attack)
        _assert_rejected(self, lambda: MODULE.validate_derivative_shape(qualification_attack))
        extra_key_attack = copy.deepcopy(self.result)
        extra_key_attack["sources"][0]["unexpected"] = "restamped"
        extra_key_attack["artifact"]["content_sha256"] = MODULE._result_semantic_sha256(extra_key_attack)
        _assert_rejected(self, lambda: MODULE.validate_derivative_shape(extra_key_attack))

    def test_canonical_serialized_result_replays_from_all_sources(self) -> None:
        replayed = MODULE.validate_derivative_bytes(
            self.serialized, dict(EXTERNAL_SOURCE_PATHS)
        )
        self.assertEqual(replayed["artifact"]["content_sha256"], self.result["artifact"]["content_sha256"])

    def test_self_rehashed_nested_result_still_requires_source_replay(self) -> None:
        attack = copy.deepcopy(self.result)
        attack["sources"][3]["styles"]["semantic_sha256"] = "0" * 64
        attack["artifact"]["content_sha256"] = MODULE._result_semantic_sha256(attack)
        with self.assertRaises(MODULE.ProfileError):
            MODULE.validate_derivative_document(
                attack, dict(EXTERNAL_SOURCE_PATHS)
            )

    def test_unrelated_cwd_cli_is_byte_identical(self) -> None:
        command = [
            sys.executable,
            str(MODULE_PATH),
            "--bea-summary-use",
            str(EXTERNAL_SOURCE_PATHS["bea_summary_use_2024"]),
            "--bea-summary-make",
            str(EXTERNAL_SOURCE_PATHS["bea_summary_make_2024"]),
            "--bea-concordance",
            str(EXTERNAL_SOURCE_PATHS["bea_industry_commodity_naics_concordance"]),
            "--naics-2017",
            str(EXTERNAL_SOURCE_PATHS["naics_2017_structure"]),
            "--naics-concordance",
            str(EXTERNAL_SOURCE_PATHS["naics_2017_to_2022_concordance"]),
            "--naics-2022",
            str(EXTERNAL_SOURCE_PATHS["naics_2022_structure"]),
        ]
        completed = subprocess.run(
            command,
            cwd="/private/tmp",
            check=False,
            capture_output=True,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            timeout=120,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr.decode())
        self.assertEqual(completed.stdout, self.serialized)
        self.assertEqual(completed.stderr, b"")


if __name__ == "__main__":
    unittest.main(verbosity=2)
