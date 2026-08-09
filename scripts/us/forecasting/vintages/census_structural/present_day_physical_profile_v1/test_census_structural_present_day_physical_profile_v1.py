#!/usr/bin/env python3
"""Adversarial tests for the present-day Census structural physical profile."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import inspect
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "census_structural_present_day_physical_profile_v1.py"
PROFILE_PATH = HERE / "census_structural_present_day_physical_profile_v1.json"
DEFAULT_AUDIT = Path("/private/tmp/census-structural-physical-audit.dZRm93")
AUDIT_ROOT = Path(
    os.environ.get("CENSUS_STRUCTURAL_PHYSICAL_AUDIT_DIR", str(DEFAULT_AUDIT))
)

spec = importlib.util.spec_from_file_location("physical_profile_under_test", MODULE_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("cannot load module under test")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def _restamp_result(value: dict[str, object]) -> bytes:
    value.pop("content_sha256", None)
    value["content_sha256"] = module.sha256_bytes(module.canonical_json_bytes(value))
    return module.canonical_json_bytes(value)


class ProfileUnitTests(unittest.TestCase):
    def test_profile_self_hash_and_no_placeholders(self) -> None:
        raw = PROFILE_PATH.read_bytes()
        profile = module.parse_json_bytes(raw, "profile test")
        self.assertNotIn(b"TO_BE_FROZEN", raw)
        self.assertEqual(
            hashlib.sha256(raw).hexdigest(),
            module.EXPECTED_PROFILE_PHYSICAL_SHA256,
        )
        self.assertEqual(
            module._profile_semantic_hash(profile),
            profile["artifact"]["content_sha256"],
        )
        self.assertEqual(profile["gates"], module.hard_false_gates())

    def test_accepted_logical_contract_pins(self) -> None:
        profile = module.load_profile()
        self.assertEqual(
            profile["artifact"]["logical_profile_semantic_sha256"],
            "c661bc84b0b9f9ee3c6ff28982721a9a9dacd14d6e73cc6859db54737429b491",
        )
        logical, hashes = module._logical_contract()
        self.assertEqual(logical["artifact"]["status"], "CANNOT_RUN")
        self.assertEqual(tuple(item["profile_id"] for item in logical["profiles"]), module.SOURCE_IDS)
        self.assertEqual(
            hashes["USCensusStructuralProfileV1.jl"],
            "e0a683586a44d0cba8129d7494c49e00e1606453c46e94b37f60d4804f450f68",
        )

    def test_observed_entrypoint_has_no_verification_bypass(self) -> None:
        signature = inspect.signature(module.parse_observed_directory)
        self.assertEqual(tuple(signature.parameters), ("source_directory",))
        source = MODULE_PATH.read_text("utf-8")
        self.assertNotIn("verify_sources", source)
        self.assertNotIn("skip_verification", source)
        self.assertNotIn("allow_unverified", source)

    def test_duplicate_json_key_and_nonfinite_rejected(self) -> None:
        with self.assertRaises(module.ProfileError):
            module.parse_json_bytes(b'{"a":1,"a":2}', "duplicate")
        with self.assertRaises(module.ProfileError):
            module.parse_json_bytes(b'{"a":NaN}', "nan")
        with self.assertRaises(module.ProfileError):
            module.parse_json_bytes(b"\xef\xbb\xbf{}", "bom")

    def test_exact_numeric_lexemes(self) -> None:
        for value in ("0", "-1", ".1", "-.1", "12.3"):
            self.assertTrue(module._is_signed_decimal(value))
        for value in ("", "+1", ".", "1.", "--1", "1e3", " 1"):
            self.assertFalse(module._is_signed_decimal(value))
        self.assertTrue(module._is_nonnegative_integer("00"))
        self.assertFalse(module._is_nonnegative_integer("-0"))

    def test_detached_profile_mutation_does_not_poison(self) -> None:
        first = module.load_profile()
        first["boundary"]["logical_contract_compatible"] = True
        first["sources"][0]["declared_source_url"] = "https://example.invalid/"
        second = module.load_profile()
        self.assertFalse(second["boundary"]["logical_contract_compatible"])
        self.assertEqual(
            second["sources"][0]["declared_source_url"],
            module.SOURCE_DECLARATIONS[0][2],
        )

    def test_module_global_status_mutation_fails_closed_and_recovers(self) -> None:
        original = module.STATUS
        try:
            module.STATUS = "READY"
            with self.assertRaises(module.ProfileError):
                module.load_profile()
        finally:
            module.STATUS = original
        self.assertEqual(module.load_profile()["artifact"]["status"], "CANNOT_RUN")

    def test_module_global_gate_mutation_fails_closed_and_recovers(self) -> None:
        original = module.HARD_FALSE_GATES
        try:
            module.HARD_FALSE_GATES = ("ready",)
            with self.assertRaises(module.ProfileError):
                module.load_profile()
        finally:
            module.HARD_FALSE_GATES = original
        self.assertFalse(module.load_profile()["gates"]["ready"])

    def test_module_global_source_mutation_fails_closed_and_recovers(self) -> None:
        original = module.SOURCE_DECLARATIONS
        try:
            module.SOURCE_DECLARATIONS = tuple(reversed(original))
            with self.assertRaises(module.ProfileError):
                module.load_profile()
        finally:
            module.SOURCE_DECLARATIONS = original
        self.assertEqual(len(module.load_profile()["sources"]), 6)

    def test_zip_prefix_suffix_and_duplicate_topology_rejected(self) -> None:
        if not AUDIT_ROOT.is_dir():
            self.skipTest("external audit bodies unavailable")
        profile = module.load_profile()
        source = profile["sources"][0]
        raw = (AUDIT_ROOT / source["filename"]).read_bytes()
        with self.assertRaises(module.ProfileError):
            module._zip_payloads(b"X" + raw, source)
        with self.assertRaises(module.ProfileError):
            module._zip_payloads(raw + b"X", source)
        buffer = io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("AIES00INV.dat", b"x")
                archive.writestr("AIES00INV.dat", b"y")
                archive.writestr("AIES00INV_FIELDS.txt", b"z")
        with self.assertRaises((module.ProfileError, zipfile.BadZipFile)):
            module._zip_payloads(buffer.getvalue(), source)

    def test_susb_cp1252_header_size_and_duplicate_decoys_rejected(self) -> None:
        if not AUDIT_ROOT.is_dir():
            self.skipTest("external audit bodies unavailable")
        profile, logical, _ = module._load_profile()
        source = profile["sources"][-1]
        logical_record = logical["profiles"][-1]
        raw = (AUDIT_ROOT / source["filename"]).read_bytes()
        cp_decoy = raw.replace(b"\x92", b"'", 1)
        with self.assertRaises(module.ProfileError):
            module._parse_susb(cp_decoy, source, logical_record)
        size_decoy = raw.replace(b"\n00,--,26,", b"\n00,--,04,", 1)
        with self.assertRaises(module.ProfileError):
            module._parse_susb(size_decoy, source, logical_record)
        header_decoy = raw.replace(b"EMPLFL_N", b"EMPLFL_R", 1)
        with self.assertRaises(module.ProfileError):
            module._parse_susb(header_decoy, source, logical_record)
        duplicate_line = raw + raw.split(b"\n", 2)[1] + b"\n"
        with self.assertRaises(module.ProfileError):
            module._parse_susb(duplicate_line, source, logical_record)


@unittest.skipUnless(AUDIT_ROOT.is_dir(), "external audit bodies unavailable")
class ObservedBundleTests(unittest.TestCase):
    _result: dict[str, object] | None = None
    _result_bytes: bytes | None = None
    _clone: tempfile.TemporaryDirectory[str] | None = None
    _clone_root: Path | None = None

    @classmethod
    def setUpClass(cls) -> None:
        cls._result = module.parse_observed_directory(AUDIT_ROOT)
        cls._result_bytes = module.canonical_json_bytes(cls._result)
        cls._clone = tempfile.TemporaryDirectory(
            prefix="census-structural-physical-tests."
        )
        cls._clone_root = Path(cls._clone.name)
        for path in AUDIT_ROOT.iterdir():
            shutil.copy2(path, cls._clone_root / path.name)

    @classmethod
    def tearDownClass(cls) -> None:
        if cls._clone is not None:
            cls._clone.cleanup()

    def test_exact_nonadmitting_result_and_source_claims(self) -> None:
        assert self._result is not None
        result = self._result
        self.assertEqual(result["status"], "CANNOT_RUN")
        self.assertEqual(
            result["role"],
            "PRESENT_DAY_PHYSICAL_LAYOUT_DIAGNOSTIC_NONADMITTING",
        )
        self.assertFalse(result["logical_constraint_compatibility"])
        self.assertFalse(result["body_to_url_provenance_claimed"])
        self.assertFalse(result["self_accepted"])
        self.assertEqual(result["gates"], module.hard_false_gates())
        self.assertEqual(tuple(record["source_id"] for record in result["records"]), module.SOURCE_IDS)
        for record in result["records"]:
            self.assertTrue(record["local_body_hash_and_size_verified"])
            self.assertTrue(record["local_raw_header_hash_and_size_verified"])
            self.assertFalse(record["local_body_to_declared_url_provenance_verified"])
            self.assertFalse(record["provider_provenance_verified"])

    def test_exact_aies_mismatch_rows_and_exemplars(self) -> None:
        assert self._result is not None
        expected_rows = (242, 302, 34, 57, 2)
        observed = tuple(
            record["physical_diagnostic"]["logical_contract_incompatible_row_count"]
            for record in self._result["records"][:5]
        )
        self.assertEqual(observed, expected_rows)
        codes = [
            {item["code"] for item in record["physical_diagnostic"]["logical_contract_mismatches"]}
            for record in self._result["records"][:5]
        ]
        self.assertIn("STRUCTURAL_FLAG_NONEMPTY", codes[0])
        self.assertIn("NEGATIVE_CV_FORBIDDEN_BY_ACCEPTED_CONTRACT", codes[1])
        self.assertIn("ACCEPTED_DIMENSION_EMPTY", codes[3])
        first = self._result["records"][0]["physical_diagnostic"]["logical_contract_mismatches"][0]["first_exemplar"]
        self.assertEqual((first["field"], first["raw_lexeme"]), ("NAICS_F", "805"))

    def test_exact_susb_membership_flags_projection_and_nonadditivity(self) -> None:
        assert self._result is not None
        susb = self._result["records"][-1]["physical_diagnostic"]
        self.assertEqual(susb["row_count"], 570105)
        self.assertEqual(susb["state_naics_group_count"], 86416)
        self.assertEqual(susb["complete_nine_size_group_count"], 29151)
        self.assertEqual(susb["incomplete_size_group_count"], 57265)
        self.assertEqual(susb["membership_pattern_count"], 74)
        self.assertEqual(
            susb["national_state_00_size_01_projection"]["row_count"], 2003
        )
        self.assertFalse(
            susb["national_state_00_size_01_projection"]["admitted_logical_table"]
        )
        self.assertEqual(
            susb["flag_lexeme_counts"]["EMPLFL_N"],
            {"G": 277234, "H": 167925, "J": 124946},
        )
        self.assertFalse(susb["firm_cross_naics_sum_performed"])
        self.assertEqual(susb["physical_format"]["quote_byte_count"], 146944)

    def test_cross_aies_exact_projection_and_no_component_sum_rule(self) -> None:
        assert self._result is not None
        cross = self._result["cross_source"]
        self.assertTrue(cross["all_detail_rows_match_exactly"])
        self.assertFalse(cross["aies51_component_additivity_required"])
        self.assertEqual(
            tuple(
                item["exact_matches"]
                for item in cross["detail_total_inventory_to_aies00"].values()
            ),
            (648, 45, 72, 8),
        )

    def test_result_replay_and_restamped_semantic_decoy_rejected(self) -> None:
        assert self._result_bytes is not None
        replayed = module.validate_observed_result_bytes(
            self._result_bytes, AUDIT_ROOT
        )
        self.assertEqual(module.canonical_json_bytes(replayed), self._result_bytes)
        noncanonical = (
            b" \t\r\n" + self._result_bytes + b" \r\n",
            self._result_bytes.replace(b"\n", b"\r\n"),
            json.dumps(replayed, ensure_ascii=False).encode("utf-8"),
        )
        for decoy in noncanonical:
            with self.assertRaises(module.ProfileError):
                module.validate_observed_result_bytes(decoy, AUDIT_ROOT)
        altered = copy.deepcopy(replayed)
        altered["records"][0]["physical_diagnostic"]["row_count"] += 1
        with self.assertRaises(module.ProfileError):
            module.validate_observed_result_bytes(_restamp_result(altered), AUDIT_ROOT)

    def test_result_exact_integer_and_provenance_restamps_rejected(self) -> None:
        assert self._result is not None
        boolean_count = copy.deepcopy(self._result)
        boolean_count["source_count"] = True
        with self.assertRaises(module.ProfileError):
            module._validate_result_shape(
                module.parse_json_bytes(_restamp_result(boolean_count), "bool result")
            )
        provenance = copy.deepcopy(self._result)
        provenance["records"][0][
            "local_body_to_declared_url_provenance_verified"
        ] = True
        with self.assertRaises(module.ProfileError):
            module._validate_result_shape(
                module.parse_json_bytes(_restamp_result(provenance), "claim result")
            )

    def test_body_header_mutation_and_mix_match_rejected(self) -> None:
        assert self._clone_root is not None
        cases = (
            "AIES00INV.zip",
            "AIES31INV.zip.headers",
            "us_state_6digitnaics_2022.txt",
        )
        for name in cases:
            path = self._clone_root / name
            original = path.read_bytes()
            try:
                mutated = bytearray(original)
                mutated[0] ^= 1
                path.write_bytes(mutated)
                with self.assertRaises(module.ProfileError, msg=name):
                    module.parse_observed_directory(self._clone_root)
            finally:
                path.write_bytes(original)
        left = self._clone_root / "AIES42INV.zip.headers"
        right = self._clone_root / "AIES44INV.zip.headers"
        left_bytes, right_bytes = left.read_bytes(), right.read_bytes()
        try:
            left.write_bytes(right_bytes)
            right.write_bytes(left_bytes)
            with self.assertRaises(module.ProfileError):
                module.parse_observed_directory(self._clone_root)
        finally:
            left.write_bytes(left_bytes)
            right.write_bytes(right_bytes)

    def test_extra_missing_relative_and_alias_paths_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="census-physical-paths.") as temp:
            root = Path(temp)
            (root / "extra").write_bytes(b"x")
            with self.assertRaises(module.ProfileError):
                module.parse_observed_directory(root)
        with self.assertRaises(module.ProfileError):
            module.parse_observed_directory(Path("relative"))
        with tempfile.TemporaryDirectory(prefix="census-physical-alias.") as temp:
            alias = Path(temp) / "alias"
            alias.symlink_to(AUDIT_ROOT, target_is_directory=True)
            with self.assertRaises(module.ProfileError):
                module.parse_observed_directory(alias.absolute())

    def test_leaf_symlink_hardlink_fifo_rejected_before_parse(self) -> None:
        expected_names = tuple(
            name
            for _, filename, _, _ in module.SOURCE_DECLARATIONS
            for name in (filename, filename + ".headers")
        )
        with tempfile.TemporaryDirectory(prefix="census-physical-links.") as temp:
            root = Path(temp)
            for name in expected_names:
                (root / name).symlink_to(AUDIT_ROOT / name)
            with self.assertRaises(module.ProfileError):
                module.parse_observed_directory(root)
        with tempfile.TemporaryDirectory(prefix="census-physical-hardlinks.") as temp:
            root = Path(temp)
            origin = Path(temp).parent / (Path(temp).name + ".origin")
            try:
                origin.write_bytes(b"x")
                for name in expected_names:
                    os.link(origin, root / name)
                with self.assertRaises(module.ProfileError):
                    module.parse_observed_directory(root)
            finally:
                origin.unlink(missing_ok=True)
        if hasattr(os, "mkfifo"):
            with tempfile.TemporaryDirectory(prefix="census-physical-fifo.") as temp:
                root = Path(temp)
                os.mkfifo(root / expected_names[0])
                for name in expected_names[1:]:
                    (root / name).write_bytes(b"x")
                with self.assertRaises(module.ProfileError):
                    module.parse_observed_directory(root)


if __name__ == "__main__":
    unittest.main(verbosity=2)
