#!/usr/bin/env python3
"""Hermetic and adversarial tests for the Census M3 fixture generator."""

from __future__ import annotations

import importlib.util
import shutil
import socket
import sys
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest import mock


HERE = Path(__file__).resolve().parent
GENERATOR_PATH = HERE / "generate_census_m3_inventory_stage_fixture.py"
RAW_SOURCE = (
    HERE
    / "raw"
    / "census_m3_naicsinvp_2026-08-06_current_vintage"
)
APPROVED_FIXTURE = (
    HERE
    / "fixtures"
    / "census_m3_naicsinvp_2026-08-06_current_vintage"
)
GENERATED_FILES = ("series_rows.csv", "identity_checks.csv", "manifest.toml")


def load_generator():
    specification = importlib.util.spec_from_file_location(
        "census_m3_inventory_stage_fixture_generator",
        GENERATOR_PATH,
    )
    if specification is None or specification.loader is None:
        raise RuntimeError("could not load Census M3 fixture generator")
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    specification.loader.exec_module(module)
    return module


class CensusM3InventoryStageFixtureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()

    def test_default_regeneration_is_offline_and_byte_identical(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "fixture"
            arguments = [
                str(GENERATOR_PATH),
                "--output-dir",
                str(output),
            ]
            with (
                mock.patch.object(sys, "argv", arguments),
                mock.patch.object(
                    socket,
                    "create_connection",
                    side_effect=AssertionError(
                        "offline fixture regeneration attempted network access"
                    ),
                ),
            ):
                self.assertEqual(self.generator.main(), 0)
            for filename in GENERATED_FILES:
                self.assertEqual(
                    (output / filename).read_bytes(),
                    (APPROVED_FIXTURE / filename).read_bytes(),
                    filename,
                )

    def test_workbook_and_receipt_hashes_are_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            output = Path(temporary) / "output"
            shutil.copytree(RAW_SOURCE, source)
            workbook = source / "naicsinvp.xlsx"
            payload = bytearray(workbook.read_bytes())
            payload[-1] ^= 1
            workbook.write_bytes(payload)
            arguments = [
                str(GENERATOR_PATH),
                "--source-dir",
                str(source),
                "--output-dir",
                str(output),
            ]
            with mock.patch.object(sys, "argv", arguments):
                with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                    self.generator.main()

        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            output = Path(temporary) / "output"
            shutil.copytree(RAW_SOURCE, source)
            receipt = source / "source_receipt.json"
            receipt.write_bytes(receipt.read_bytes() + b"\n")
            arguments = [
                str(GENERATOR_PATH),
                "--source-dir",
                str(source),
                "--output-dir",
                str(output),
            ]
            with mock.patch.object(sys, "argv", arguments):
                with self.assertRaisesRegex(
                    ValueError,
                    "receipt SHA-256 mismatch",
                ):
                    self.generator.main()

    def test_missing_zero_and_code_mutations_are_not_interchangeable(self):
        rows = self.generator.parse_source_rows(RAW_SOURCE / "naicsinvp.xlsx")
        current_index = next(
            index
            for index, row in enumerate(rows)
            if row.series_id == "AMTMTI" and row.year == 2026
        )

        zero_rows = list(rows)
        current = zero_rows[current_index]
        values = list(current.values)
        self.assertIsNone(values[6])
        values[6] = 0
        zero_rows[current_index] = replace(current, values=tuple(values))
        with self.assertRaisesRegex(
            ValueError,
            "numeric cell count|explicit zero|missing pattern",
        ):
            self.generator.validate_source_rows(zero_rows)

        missing_rows = list(rows)
        current = missing_rows[current_index]
        values = list(current.values)
        self.assertIsInstance(values[5], int)
        values[5] = None
        missing_rows[current_index] = replace(current, values=tuple(values))
        with self.assertRaisesRegex(
            ValueError,
            "numeric cell count|missing pattern",
        ):
            self.generator.validate_source_rows(missing_rows)

        self.assertIsNotNone(
            self.generator.SERIES_PATTERN.fullmatch("AMTMTI")
        )
        self.assertIsNotNone(
            self.generator.SERIES_PATTERN.fullmatch("U25SWI")
        )
        for invalid in ("BMTMTI", "AMTMXX", "AMTMT", "AMTMTII"):
            self.assertIsNone(
                self.generator.SERIES_PATTERN.fullmatch(invalid),
                invalid,
            )

    def test_identity_builder_rejects_partial_or_nonzero_identity(self):
        rows = self.generator.parse_source_rows(RAW_SOURCE / "naicsinvp.xlsx")
        current_index = next(
            index
            for index, row in enumerate(rows)
            if row.series_id == "AMTMMI" and row.year == 2026
        )
        changed_rows = list(rows)
        current = changed_rows[current_index]
        values = list(current.values)
        values[5] += 1
        changed_rows[current_index] = replace(current, values=tuple(values))
        with self.assertRaisesRegex(ValueError, "identity statuses"):
            self.generator.identity_rows(changed_rows)


if __name__ == "__main__":
    unittest.main()
