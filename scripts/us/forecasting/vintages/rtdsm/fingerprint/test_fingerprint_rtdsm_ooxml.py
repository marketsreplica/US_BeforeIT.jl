#!/usr/bin/env python3

from __future__ import annotations

import copy
import importlib.util
import json
import os
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path

sys.dont_write_bytecode = True

MODULE_PATH = Path(__file__).with_name("fingerprint_rtdsm_ooxml.py").resolve()
SPEC = importlib.util.spec_from_file_location("fingerprint_rtdsm_ooxml", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load RTDSM fingerprint module")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

PROFILE_PATH = MODULE_PATH.parent.parent / "rtdsm_quarterly_profile.json"
FIXTURE_SPEC = MODULE.SeriesSpec(
    series_id="NOUTPUT",
    filename="NOUTPUTQvQd.xlsx",
    sheet_name="NOUTPUT",
    header_prefix="NOUTPUT",
    first_supported_vintage="1965Q4",
    source_semantics="synthetic nominal output",
    protocol_mapping="nominal_gdp",
    mapping_status="COMPARABLE_AFTER_MILLIONS_TO_BILLIONS_AND_SOURCE_PRECISION",
    forbidden_direct_mapping=False,
)


def _zip_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    return info


def write_fixture(
    path: Path,
    *,
    sheet_name: str = "NOUTPUT",
    first_vintage: str = "1965Q4",
    second_vintage: str = "1966Q1",
    formula: bool = False,
    unknown_token: bool = False,
    omit_b2: bool = False,
    omit_b3: bool = False,
    external_relationship: bool = False,
    unsafe_member: bool = False,
    duplicate_member: bool = False,
) -> None:
    first_year, first_quarter = first_vintage.split("Q")
    second_year, second_quarter = second_vintage.split("Q")
    prefix = "NOUTPUT"
    strings = [
        "DATE",
        prefix + first_year[-2:] + "Q" + first_quarter,
        prefix + second_year[-2:] + "Q" + second_quarter,
        first_year + ":Q" + str(int(first_quarter) - 1 or 4),
        first_year + ":Q" + first_quarter,
        "#N/A",
        "UNDOCUMENTED",
    ]
    shared_items = "".join(
        "<si><t>{}</t></si>".format(value) for value in strings
    )
    b2 = (
        ""
        if omit_b2
        else (
            '<c r="B2" t="s"><v>6</v></c>'
            if unknown_token
            else (
                '<c r="B2"><f>1+1</f><v>100.0</v></c>'
                if formula
                else '<c r="B2"><v>100.0</v></c>'
            )
        )
    )
    b3 = "" if omit_b3 else '<c r="B3" t="s"><v>5</v></c>'
    worksheet = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/'
        'spreadsheetml/2006/main">'
        '<dimension ref="A1:C3"/>'
        "<sheetData>"
        '<row r="1">'
        '<c r="A1" t="s"><v>0</v></c>'
        '<c r="B1" t="s"><v>1</v></c>'
        '<c r="C1" t="s"><v>2</v></c>'
        "</row>"
        '<row r="2"><c r="A2" t="s"><v>3</v></c>'
        + b2
        + '<c r="C2"><v>100.0</v></c></row>'
        '<row r="3"><c r="A3" t="s"><v>4</v></c>'
        + b3
        + '<c r="C3"><v>101.0</v></c></row>'
        '<row r="4"/>'
        "</sheetData></worksheet>"
    )
    target_mode = ' TargetMode="External"' if external_relationship else ""
    parts = {
        "[Content_Types].xml": (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
            'content-types"><Default Extension="xml" '
            'ContentType="application/xml"/></Types>'
        ),
        "_rels/.rels": (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/'
            '2006/relationships"><Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
            'relationships/officeDocument" Target="xl/workbook.xml"/>'
            "</Relationships>"
        ),
        "xl/workbook.xml": (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/'
            'spreadsheetml/2006/main" xmlns:r="http://schemas.'
            'openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="{}" sheetId="1" r:id="rId1"/>'
            "</sheets></workbook>"
        ).format(sheet_name),
        "xl/_rels/workbook.xml.rels": (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/'
            '2006/relationships"><Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
            'relationships/worksheet" Target="worksheets/sheet1.xml"{} />'
            "</Relationships>"
        ).format(target_mode),
        "xl/worksheets/sheet1.xml": worksheet,
        "xl/styles.xml": (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<styleSheet xmlns="http://schemas.openxmlformats.org/'
            'spreadsheetml/2006/main"><cellXfs count="1">'
            '<xf numFmtId="0"/></cellXfs></styleSheet>'
        ),
        "xl/sharedStrings.xml": (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<sst xmlns="http://schemas.openxmlformats.org/'
            'spreadsheetml/2006/main" count="7" uniqueCount="7">'
            + shared_items
            + "</sst>"
        ),
    }
    with zipfile.ZipFile(path, "w") as archive:
        for name, value in parts.items():
            archive.writestr(_zip_info(name), value.encode("utf-8"))
        if unsafe_member:
            archive.writestr(_zip_info("../unsafe.xml"), b"<unsafe/>")
        if duplicate_member:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                archive.writestr(
                    _zip_info("xl/sharedStrings.xml"),
                    parts["xl/sharedStrings.xml"].encode("utf-8"),
                )


class RTDSMFingerprintTests(unittest.TestCase):
    def parse_fixture(
        self,
        root: Path,
        *,
        spec: object = FIXTURE_SPEC,
        selected: object = (("1965Q4", "1965Q3"), ("1966Q1", "1965Q4")),
        **kwargs: object,
    ) -> object:
        path = root / "NOUTPUTQvQd.xlsx"
        write_fixture(path, **kwargs)
        return MODULE.parse_panel(path.resolve(), spec, selected)

    def test_profile_is_exact_and_forbids_two_direct_mappings(self) -> None:
        profile, specs = MODULE.load_profile(PROFILE_PATH.resolve())
        self.assertEqual(
            MODULE.sha256_file(PROFILE_PATH),
            MODULE.EXPECTED_PROFILE_SHA256,
        )
        self.assertEqual(len(specs), 5)
        self.assertEqual(
            {
                spec.series_id
                for spec in specs
                if spec.forbidden_direct_mapping
            },
            {"P", "PCON"},
        )
        self.assertFalse(profile["redistribution_authorized"])
        self.assertFalse(profile["model_training_authorized_by_contract"])
        crosschecks = MODULE._selected_crosscheck_records(profile)
        self.assertEqual(
            tuple(
                (
                    record["reference_period"],
                    record["bea_fingerprint_sha256"],
                )
                for record in crosschecks
            ),
            (
                (
                    "2019Q4",
                    "f6c60ba8eccda00b197dc6d915abc77575bd073ef1e4f6bf598d4ade9ea2e2a4",
                ),
                (
                    "2021Q2",
                    "889d080250ffe5d9e3ff4e8bea35195b7ba521f4a48f79a7609ab1facde57711",
                ),
            ),
        )

    def test_profile_tamper_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve() / "profile.json"
            path.write_bytes(PROFILE_PATH.read_bytes() + b" ")
            with self.assertRaisesRegex(MODULE.FingerprintError, "SHA-256 drifted"):
                MODULE.load_profile(path)

    def test_synthetic_panel_parses_and_classifies_missingness(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            panel = self.parse_fixture(Path(temporary).resolve())
            self.assertEqual(panel.vintage_start, "1965Q4")
            self.assertEqual(panel.vintage_end, "1966Q1")
            self.assertEqual(panel.reference_period_start, "1965Q3")
            self.assertEqual(panel.reference_period_end, "1965Q4")
            self.assertEqual(panel.numeric_cell_count, 3)
            self.assertEqual(panel.structural_future_cell_count, 1)
            self.assertEqual(panel.source_missing_marker_count, 0)
            self.assertEqual(panel.unknown_absent_cell_count, 0)
            self.assertEqual(panel.trailing_empty_row_element_count, 1)
            self.assertEqual(
                panel.selected[("1965Q4", "1965Q3")]["evidence_grade"],
                "CURATED_RECONSTRUCTION",
            )

    def test_century_rollover_is_unrolled_sequentially(self) -> None:
        rollover = copy.copy(FIXTURE_SPEC)
        object.__setattr__(rollover, "first_supported_vintage", "1999Q4")
        with tempfile.TemporaryDirectory() as temporary:
            panel = self.parse_fixture(
                Path(temporary).resolve(),
                spec=rollover,
                selected=(("1999Q4", "1999Q3"), ("2000Q1", "1999Q4")),
                first_vintage="1999Q4",
                second_vintage="2000Q1",
            )
            self.assertEqual(panel.vintage_start, "1999Q4")
            self.assertEqual(panel.vintage_end, "2000Q1")

    def test_vintage_gap_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(
                MODULE.FingerprintError,
                "vintage .* sequence drifted",
            ):
                self.parse_fixture(
                    Path(temporary).resolve(),
                    selected=(),
                    second_vintage="1966Q2",
                )

    def test_formula_external_relationship_and_wrong_sheet_are_rejected(self) -> None:
        cases = (
            ({"formula": True}, "formulas are forbidden"),
            ({"external_relationship": True}, "external OOXML relationship"),
            ({"sheet_name": "WRONG"}, "sheet name drifted"),
        )
        for kwargs, message in cases:
            with self.subTest(message=message):
                with tempfile.TemporaryDirectory() as temporary:
                    with self.assertRaisesRegex(MODULE.FingerprintError, message):
                        self.parse_fixture(
                            Path(temporary).resolve(),
                            selected=(),
                            **kwargs,
                        )

    def test_unsafe_duplicate_and_undocumented_content_are_rejected(self) -> None:
        cases = (
            ({"unsafe_member": True}, "unsafe member"),
            ({"duplicate_member": True}, "duplicate member"),
            ({"unknown_token": True}, "undocumented string token"),
        )
        for kwargs, message in cases:
            with self.subTest(message=message):
                with tempfile.TemporaryDirectory() as temporary:
                    with self.assertRaisesRegex(MODULE.FingerprintError, message):
                        self.parse_fixture(
                            Path(temporary).resolve(),
                            selected=(),
                            **kwargs,
                        )

    def test_interior_absence_is_unknown_and_future_absence_is_structural(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            panel = self.parse_fixture(
                Path(temporary).resolve(),
                selected=(("1966Q1", "1965Q4"),),
                omit_b2=True,
                omit_b3=True,
            )
            self.assertEqual(panel.unknown_absent_cell_count, 1)
            self.assertEqual(panel.structural_future_cell_count, 1)

    def test_source_missing_marker_is_not_zero_or_unknown(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary).resolve() / "NOUTPUTQvQd.xlsx"
            write_fixture(path, unknown_token=False)
            # Replace the numeric B2 token with the profiled #N/A shared string.
            with zipfile.ZipFile(path, "r") as source:
                payloads = {
                    info.filename: source.read(info.filename)
                    for info in source.infolist()
                }
            payloads["xl/worksheets/sheet1.xml"] = payloads[
                "xl/worksheets/sheet1.xml"
            ].replace(b'<c r="B2"><v>100.0</v></c>', b'<c r="B2" t="s"><v>5</v></c>')
            replacement = path.with_name("replacement.xlsx")
            with zipfile.ZipFile(replacement, "w") as archive:
                for name, value in payloads.items():
                    archive.writestr(_zip_info(name), value)
            path.unlink()
            replacement.rename(path)
            panel = MODULE.parse_panel(path, FIXTURE_SPEC, ())
            self.assertEqual(panel.source_missing_marker_count, 1)
            self.assertEqual(panel.unknown_unsupported_token_count, 0)

    def test_symlink_and_hardlink_raw_paths_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            original = root / "original.xlsx"
            write_fixture(original)
            alias = root / "NOUTPUTQvQd.xlsx"
            alias.symlink_to(original)
            with self.assertRaisesRegex(MODULE.FingerprintError, "unsafe"):
                MODULE.parse_panel(alias, FIXTURE_SPEC, ())
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            path = root / "NOUTPUTQvQd.xlsx"
            write_fixture(path)
            os.link(path, root / "hardlink.xlsx")
            with self.assertRaisesRegex(MODULE.FingerprintError, "single-link"):
                MODULE.parse_panel(path, FIXTURE_SPEC, ())

    def test_content_address_writer_is_idempotent_and_no_clobber(self) -> None:
        data = MODULE.canonical_json_bytes({"value": 1})
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary).resolve() / "artifacts"
            first = MODULE.write_content_addressed(output, data)
            metadata = first.stat()
            second = MODULE.write_content_addressed(output, data)
            self.assertEqual(first, second)
            self.assertEqual(metadata.st_ino, second.stat().st_ino)
            self.assertEqual(second.read_bytes(), data)
            self.assertEqual(second.stat().st_nlink, 1)

    def test_dangling_destination_symlink_is_rejected_and_preserved(self) -> None:
        data = MODULE.canonical_json_bytes({"value": 1})
        digest = MODULE.sha256_bytes(data)
        filename = (
            "rtdsm-quarterly-research-diagnostic-sha256-" + digest + ".json"
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            output = root / "artifacts"
            output.mkdir()
            destination = output / filename
            destination.symlink_to(root / "absent")
            with self.assertRaisesRegex(MODULE.FingerprintError, "unsafe"):
                MODULE.write_content_addressed(output, data)
            self.assertTrue(destination.is_symlink())

    def test_checked_artifact_is_unique_canonical_and_valid(self) -> None:
        artifact_dir = MODULE_PATH.parent / "artifacts"
        artifacts = sorted(artifact_dir.glob("*.json"))
        self.assertEqual(len(artifacts), 1)
        path = artifacts[0]
        digest = path.name.removeprefix(
            "rtdsm-quarterly-research-diagnostic-sha256-"
        ).removesuffix(".json")
        data = path.read_bytes()
        self.assertEqual(MODULE.sha256_bytes(data), digest)
        document = MODULE.parse_json_bytes(data, "checked artifact")
        self.assertEqual(MODULE.canonical_json_bytes(document), data)
        MODULE.validate_compact_diagnostic(document)
        self.assertEqual(
            [panel["raw_sha256"] for panel in document["panels"]],
            [
                "6ef256144270f7ee35ee58c51136e3f8a31851fbaaed4385f8770bbf3afb1f09",
                "a89244fc00b14f50d2faf8aa146676bb6ff1bd3914854fc3facde1bd931bc180",
                "4694f0b5c84d2e79954d3f272a6156205dd6e94120a0f07e16ba99309f77c2e0",
                "857c29e2bf34f934976997caa3467f72406ef6065edfd7415edfdec8bd433c24",
                "b37594b3b1a363ae561aedce0d0633e1e53ae08f1fd83507b625be6c1450f150",
            ],
        )
        self.assertEqual(
            document["crosschecks"][1]["bea_annual_update_caveat"],
            (
                "THIS_RELEASE_INCLUDES_THE_2021_ANNUAL_UPDATE_AND_REVISED_"
                "HISTORY_MUST_NOT_BE_TREATED_AS_A_STANDARD_WITHIN_DEFINITION_"
                "VINTAGE"
            ),
        )

    def test_validator_rejects_gate_summary_and_concept_tamper(self) -> None:
        path = next((MODULE_PATH.parent / "artifacts").glob("*.json"))
        document = json.loads(path.read_text())
        mutations = []
        gate = copy.deepcopy(document)
        gate["gates"]["ready"] = True
        mutations.append((gate, "hard-false gates"))
        summary = copy.deepcopy(document)
        summary["summary"]["forbidden_direct_concept_mismatch_count"] = 1
        mutations.append((summary, "summary drifted"))
        concept = copy.deepcopy(document)
        concept["crosschecks"][0]["checks"][2]["anomaly_code"] = "SOURCE_CONFLICT"
        mutations.append((concept, "concept mismatch was lost"))
        for value, message in mutations:
            with self.subTest(message=message):
                with self.assertRaisesRegex(MODULE.FingerprintError, message):
                    MODULE.validate_compact_diagnostic(value)

    def test_used_is_provenance_relation_and_other_is_documented(self) -> None:
        path = next((MODULE_PATH.parent / "artifacts").glob("*.json"))
        document = json.loads(path.read_text())
        provenance = document["provenance"]
        self.assertTrue(provenance["used_is_relation_not_status"])
        self.assertTrue(
            all(item["provenance_relation"] == "used" for item in provenance["used"])
        )
        self.assertIn("REQUIRES_REASON", provenance["other_policy"])
        self.assertIn("NEVER_COERCED", provenance["unknown_policy"])

    def test_validator_rejects_every_provenance_field_mutation(self) -> None:
        path = next((MODULE_PATH.parent / "artifacts").glob("*.json"))
        document = json.loads(path.read_text())
        mutations = []

        malformed = copy.deepcopy(document)
        malformed["provenance"] = "Used"
        mutations.append((malformed, "provenance record is malformed"))

        missing_key = copy.deepcopy(document)
        missing_key["provenance"].pop("unknown_policy")
        mutations.append((missing_key, "provenance keys drifted"))

        extra_key = copy.deepcopy(document)
        extra_key["provenance"]["Other"] = "bare status"
        mutations.append((extra_key, "provenance keys drifted"))

        relation_boundary = copy.deepcopy(document)
        relation_boundary["provenance"]["used_is_relation_not_status"] = "Used"
        mutations.append((relation_boundary, "relation/status boundary drifted"))

        other_policy = copy.deepcopy(document)
        other_policy["provenance"]["other_policy"] = "Other"
        mutations.append((other_policy, "Other policy drifted"))

        unknown_policy = copy.deepcopy(document)
        unknown_policy["provenance"]["unknown_policy"] = (
            "UNKNOWN_COERCE_TO_ZERO"
        )
        mutations.append((unknown_policy, "unknown policy drifted"))

        used_type = copy.deepcopy(document)
        used_type["provenance"]["used"] = "Used"
        mutations.append((used_type, "used provenance list drifted"))

        used_count = copy.deepcopy(document)
        used_count["provenance"]["used"].pop()
        mutations.append((used_count, "used provenance list drifted"))

        malformed_record = copy.deepcopy(document)
        malformed_record["provenance"]["used"][0] = "Used"
        mutations.append((malformed_record, "record 1 is malformed"))

        missing_record_key = copy.deepcopy(document)
        missing_record_key["provenance"]["used"][0].pop("role")
        mutations.append((missing_record_key, "record 1 keys drifted"))

        extra_record_key = copy.deepcopy(document)
        extra_record_key["provenance"]["used"][0]["Other"] = "bare status"
        mutations.append((extra_record_key, "record 1 keys drifted"))

        malformed_hash = copy.deepcopy(document)
        malformed_hash["provenance"]["used"][0]["used_artifact_sha256"] = "Used"
        mutations.append((malformed_hash, "record 1 artifact hash is malformed"))

        rebound_hash = copy.deepcopy(document)
        rebound_hash["provenance"]["used"][0]["used_artifact_sha256"] = "0" * 64
        mutations.append((rebound_hash, "record 1 artifact binding drifted"))

        role = copy.deepcopy(document)
        role["provenance"]["used"][0]["role"] = "Other"
        mutations.append((role, "record 1 role drifted"))

        reversed_bindings = copy.deepcopy(document)
        reversed_bindings["provenance"]["used"].reverse()
        mutations.append((reversed_bindings, "record 1 artifact binding drifted"))

        for bare_relation in ("Used", "Other", "UNKNOWN"):
            relation = copy.deepcopy(document)
            relation["provenance"]["used"][0][
                "provenance_relation"
            ] = bare_relation
            mutations.append((relation, "record 1 relation drifted"))

        for value, message in mutations:
            with self.subTest(message=message):
                with self.assertRaisesRegex(MODULE.FingerprintError, message):
                    MODULE.validate_compact_diagnostic(value)

    def test_validator_rejects_coordinated_bea_binding_mutations(self) -> None:
        path = next((MODULE_PATH.parent / "artifacts").glob("*.json"))
        document = json.loads(path.read_text())
        mutations = []

        for index, replacement in ((0, "0" * 64), (1, "1" * 64)):
            rebound = copy.deepcopy(document)
            rebound["crosschecks"][index][
                "bea_fingerprint_sha256"
            ] = replacement
            rebound["provenance"]["used"][index][
                "used_artifact_sha256"
            ] = replacement
            period = rebound["crosschecks"][index]["reference_period"]
            mutations.append(
                (
                    rebound,
                    f"cross-check {period} bea_fingerprint_sha256 binding drifted",
                )
            )

        swapped = copy.deepcopy(document)
        first_hash = swapped["crosschecks"][0]["bea_fingerprint_sha256"]
        second_hash = swapped["crosschecks"][1]["bea_fingerprint_sha256"]
        swapped["crosschecks"][0]["bea_fingerprint_sha256"] = second_hash
        swapped["crosschecks"][1]["bea_fingerprint_sha256"] = first_hash
        swapped["provenance"]["used"].reverse()
        mutations.append(
            (
                swapped,
                "cross-check 2019Q4 bea_fingerprint_sha256 binding drifted",
            )
        )

        for value, message in mutations:
            with self.subTest(message=message):
                with self.assertRaisesRegex(MODULE.FingerprintError, message):
                    MODULE.validate_compact_diagnostic(value)


if __name__ == "__main__":
    unittest.main(verbosity=2)
