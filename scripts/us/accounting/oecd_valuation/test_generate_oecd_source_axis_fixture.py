#!/usr/bin/env python3
"""Hermetic regeneration test for the archived OECD valuation fixture."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


HERE = Path(__file__).resolve().parent
GENERATOR_PATH = HERE / "generate_oecd_source_axis_fixture.py"
APPROVED_FIXTURE = HERE / "fixtures" / "oecd_sut_usa_2024_v2"
GENERATED_FILES = (
    "axis_codes.csv",
    "cells.csv",
    "identity_evaluations.csv",
    "manifest.toml",
    "source_receipts.json",
    "source_totals.csv",
    "t1610_nonbasic_quarantine.csv",
)


def load_generator():
    specification = importlib.util.spec_from_file_location(
        "oecd_source_axis_fixture_generator",
        GENERATOR_PATH,
    )
    if specification is None or specification.loader is None:
        raise RuntimeError("could not load OECD valuation fixture generator")
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    specification.loader.exec_module(module)
    return module


class OECDSourceAxisFixtureRegenerationTest(unittest.TestCase):
    def test_default_regeneration_is_offline_and_byte_identical(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            arguments = [
                str(GENERATOR_PATH),
                "--output-dir",
                str(output),
            ]
            with (
                mock.patch.object(sys, "argv", arguments),
                mock.patch.object(
                    generator.urllib.request,
                    "urlopen",
                    side_effect=AssertionError(
                        "default regeneration attempted a network call"
                    ),
                ),
            ):
                self.assertEqual(generator.main(), 0)

            for filename in GENERATED_FILES:
                self.assertEqual(
                    (output / filename).read_bytes(),
                    (APPROVED_FIXTURE / filename).read_bytes(),
                    filename,
                )


if __name__ == "__main__":
    unittest.main()
