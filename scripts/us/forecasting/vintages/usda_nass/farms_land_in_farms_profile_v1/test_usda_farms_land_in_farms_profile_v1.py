#!/usr/bin/env python3

from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import tempfile
import unittest

import USDAFarmsLandInFarmsProfileV1 as profile


class USDAProfileTests(unittest.TestCase):
    def test_profile_and_sources(self) -> None:
        document = profile.validate_profile()
        self.assertEqual(document["artifact"]["status"], profile.STATUS)
        self.assertFalse(any(document["gates"].values()))
        self.assertEqual(document["blocking_reasons"], list(profile.BLOCKING_REASONS))
        self.assertEqual(len(document["sources"]), 5)

    def test_exact_full_table_projection(self) -> None:
        fragments: list[tuple[str, float, float]] = []
        for index, row in enumerate(profile.EXPECTED_ROWS):
            for column, value in enumerate(row):
                token = f"{value:,}"
                fragments.append((token, profile.EXPECTED_X[column], profile.EXPECTED_Y[index]))
        rows = profile._extract_table_from_fragments(fragments)
        self.assertEqual(len(rows), 8)
        self.assertEqual(rows[6]["year"], 2024)
        self.assertEqual(rows[6]["number_of_farms"], 1_880_000)
        self.assertEqual(rows[7]["number_of_farms"], 1_865_000)

        for attack in ("wrong_value", "wrong_position", "duplicate", "missing"):
            changed = list(fragments)
            if attack == "wrong_value":
                changed[25] = ("1,880,001", changed[25][1], changed[25][2])
            elif attack == "wrong_position":
                changed[25] = (changed[25][0], changed[25][1] + 1.0, changed[25][2])
            elif attack == "duplicate":
                changed.append(changed[25])
            else:
                changed.pop(25)
            with self.assertRaises(profile.ProfileError):
                profile._extract_table_from_fragments(changed)

    def test_integer_tokens_fail_closed(self) -> None:
        for token in ("01", "+1", "1.0", "1e3", "NaN", "١", "1,00", "1 000", ""):
            with self.assertRaises(profile.ProfileError):
                profile._parse_integer_token(token, "probe")

    def test_stored_fingerprint_and_restamps(self) -> None:
        expected = profile._expected_fingerprint()
        self.assertEqual(profile.validate_fingerprint(copy.deepcopy(expected)), expected)
        self.assertEqual(profile.validate_stored_fingerprint(), expected)

        attacks = []
        changed = copy.deepcopy(expected)
        changed["selected_profile"]["value"] = 1_880_001
        attacks.append(changed)
        changed = copy.deepcopy(expected)
        changed["model_mapping"]["one_farm_equals_one_model_firm"] = True
        attacks.append(changed)
        changed = copy.deepcopy(expected)
        changed["gates"]["origin_admissible"] = True
        attacks.append(changed)
        changed = copy.deepcopy(expected)
        changed["blocking_reasons"] = []
        attacks.append(changed)
        for changed in attacks:
            payload = copy.deepcopy(changed)
            payload["artifact"].pop("content_sha256")
            changed["artifact"]["content_sha256"] = profile.canonical_sha256(payload)
            with self.assertRaises(profile.ProfileError):
                profile.validate_fingerprint(changed)

    def test_source_link_and_hash_attacks(self) -> None:
        document = profile.validate_profile()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            for row in document["sources"]:
                source = profile.REPOSITORY_ROOT / row["path"]
                target = root / row["path"]
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read_bytes())
            self.assertIsInstance(profile.validate_profile(), dict)

            first = root / document["sources"][0]["path"]
            first.write_bytes(first.read_bytes() + b"\n")
            with self.assertRaises(profile.ProfileError):
                for binding_id, relative, expected in profile.SOURCE_PINS:
                    data = profile._stable_read(root / relative, 64 * 1024 * 1024)
                    if profile._sha256(data) != expected:
                        profile._fail(f"source hash mismatch: {binding_id}")

    def test_pdf_path_safety_and_optional_exact_replay(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "target.pdf"
            target.write_bytes(b"%PDF-1.7\n%%EOF\n")
            linked = root / "linked.pdf"
            linked.symlink_to(target)
            with self.assertRaises(profile.ProfileError):
                profile._stable_read(linked, profile.MAX_PDF_BYTES)
            hard = root / "hard.pdf"
            os.link(target, hard)
            with self.assertRaises(profile.ProfileError):
                profile._stable_read(target, profile.MAX_PDF_BYTES)

        external = os.environ.get("USDA_NASS_EXACT_PDF")
        if external:
            self.assertEqual(
                profile.parse_exact_pdf(Path(external)),
                profile._expected_fingerprint(),
            )

    def test_json_types_and_canonicalization(self) -> None:
        with self.assertRaises(profile.ProfileError):
            profile.canonical_sha256({"bad": 1.0})
        with self.assertRaises(profile.ProfileError):
            profile.canonical_sha256({1: "bad"})
        encoded = json.loads(profile._canonical_bytes(profile._expected_fingerprint()))
        self.assertEqual(encoded["selected_profile"]["value"], 1_880_000)


if __name__ == "__main__":
    unittest.main(verbosity=2)
