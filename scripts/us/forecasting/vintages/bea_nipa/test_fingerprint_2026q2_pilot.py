#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

MODULE_PATH = Path(__file__).with_name("fingerprint_2026q2_pilot.py")
SPEC = importlib.util.spec_from_file_location(
    "fingerprint_2026q2_pilot",
    MODULE_PATH,
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load fingerprint_2026q2_pilot.py")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class FingerprintContractTests(unittest.TestCase):
    def test_pilot_identity_and_target_coverage(self) -> None:
        self.assertEqual(
            MODULE.SCHEMA_VERSION,
            "beforeit-us-bea-nipa-content-fingerprint.v2",
        )
        self.assertEqual(
            MODULE.PARSER_VERSION,
            "beforeit-us-bea-nipa-ooxml-parser.v2",
        )
        self.assertEqual(
            MODULE.JSON_CANONICALIZATION,
            "utf8_sorted_keys_compact_json_lf",
        )
        self.assertEqual(
            MODULE.SEMANTIC_IDENTITY_SCOPE,
            "RAW_WORKBOOK_BYTES_RELEASE_MAPPING_PARSED_VALUES_AND_PARSER_BYTES",
        )
        metadata = MODULE.artifact_metadata(MODULE_PATH)
        self.assertFalse(metadata["execution_environment_included"])
        self.assertFalse(metadata["repository_state_included"])
        self.assertNotIn("python_version", metadata)
        self.assertNotIn("platform", metadata)
        self.assertNotIn("repository_head", metadata)
        self.assertEqual(
            metadata["parser_sha256"],
            MODULE.sha256_file(MODULE_PATH),
        )
        self.assertEqual(MODULE.RELEASE_ID, "r2026q2_advance")
        self.assertEqual(
            MODULE.RAW_BUNDLE_SHA256,
            "9f4152937f58d777feb0f6562c1b1ca3681b0e51c1aa03b486fd5d29d1e794ff",
        )
        self.assertEqual(len(MODULE.WORKBOOK_SPECS), 2)
        self.assertEqual(
            sum(row.byte_count for row in MODULE.WORKBOOK_SPECS),
            8_927_142,
        )
        self.assertEqual(
            {row.section_id for row in MODULE.WORKBOOK_SPECS},
            {"1", "2"},
        )
        self.assertEqual(
            {row.target_id for row in MODULE.TARGET_SPECS},
            {
                "core_pce_price_index",
                "gdp_deflator",
                "nominal_gdp",
                "pce_price_index",
                "real_gdp",
            },
        )

    def test_excel_column_round_trip(self) -> None:
        for name in ("A", "D", "Z", "AA", "LI", "ZZ"):
            self.assertEqual(
                MODULE.column_name(MODULE.column_number(name)),
                name,
            )
        with self.assertRaises(MODULE.FingerprintError):
            MODULE.column_number("A1")
        with self.assertRaises(MODULE.FingerprintError):
            MODULE.column_name(0)

    def test_quarter_sequence(self) -> None:
        periods = MODULE.quarter_sequence("1947Q1", "2026Q2")
        self.assertEqual(len(periods), 318)
        self.assertEqual(periods[:2], ["1947Q1", "1947Q2"])
        self.assertEqual(periods[-2:], ["2026Q1", "2026Q2"])
        with self.assertRaises(MODULE.FingerprintError):
            MODULE.quarter_sequence("2026Q2", "2026Q1")

    def test_concept_and_published_value_normalization(self) -> None:
        self.assertEqual(
            MODULE.normalized_concept("  PCE excluding food and energy\\4\\"),
            "PCE excluding food and energy",
        )
        self.assertEqual(
            MODULE.published_value("130.00700000000001", 3, "A1"),
            "130.007",
        )
        self.assertEqual(
            MODULE.published_value("32475210", 0, "A1"),
            "32475210",
        )
        self.assertEqual(
            MODULE.published_value(MODULE.MISSING_MARKER, 3, "A1"),
            MODULE.MISSING_MARKER,
        )

    def test_canonical_json_and_content_addressing(self) -> None:
        data = MODULE.canonical_json_bytes({"z": 1, "a": False})
        self.assertEqual(data, b'{"a":false,"z":1}\n')
        self.assertEqual(
            json.loads(data),
            {"a": False, "z": 1},
        )
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            first = MODULE.write_content_addressed(output, data)
            repeated = MODULE.write_content_addressed(output, data)
            self.assertEqual(first, repeated)
            self.assertEqual(first.read_bytes(), data)
            self.assertIn(MODULE.sha256_bytes(data), first.name)

    def test_raw_root_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "raw"
            root.mkdir()
            workbook = root / "book.xlsx"
            workbook.write_bytes(b"PK\x03\x04synthetic")
            self.assertEqual(
                MODULE.safe_raw_path(root, workbook),
                workbook.resolve(),
            )
            outside = Path(directory) / "outside.xlsx"
            outside.write_bytes(b"PK\x03\x04outside")
            with self.assertRaises(MODULE.FingerprintError):
                MODULE.safe_raw_path(root, outside)


if __name__ == "__main__":
    unittest.main()
