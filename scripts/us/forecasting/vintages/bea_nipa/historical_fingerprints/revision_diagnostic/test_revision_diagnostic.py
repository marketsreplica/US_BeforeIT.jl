#!/usr/bin/env python3

from __future__ import annotations

import copy
import importlib.util
import shutil
import sys
import tempfile
import unittest
from decimal import Decimal, localcontext
from pathlib import Path

sys.dont_write_bytecode = True

MODULE_PATH = Path(__file__).with_name("build_revision_diagnostic.py").resolve()
SPEC = importlib.util.spec_from_file_location("build_revision_diagnostic", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load revision diagnostic generator")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

SOURCE_DIR = MODULE_PATH.parent.parent / "fingerprints"


def official_documents() -> dict[str, dict[str, object]]:
    return MODULE.load_pinned_sources(SOURCE_DIR)


def copied_source_dir(root: Path) -> Path:
    source = root / "sources"
    source.mkdir()
    for spec in MODULE.SOURCES:
        shutil.copyfile(SOURCE_DIR / spec.filename, source / spec.filename)
    return source


def mutate_target(
    document: dict[str, object],
    target_id: str = "nominal_gdp",
) -> dict[str, object]:
    targets = document["targets"]
    assert isinstance(targets, list)
    return next(
        target
        for target in targets
        if isinstance(target, dict) and target.get("target_id") == target_id
    )


class RevisionDiagnosticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.documents = official_documents()

    def source_document(self, role: str) -> dict[str, object]:
        return copy.deepcopy(self.documents[role])

    def test_official_build_has_exact_scope_and_hard_false_gates(self) -> None:
        diagnostic = MODULE.build_diagnostic(SOURCE_DIR)
        self.assertEqual(diagnostic["artifact"]["status"], MODULE.STATUS)
        self.assertEqual(diagnostic["artifact"]["gates"], MODULE.false_gates())
        self.assertEqual(
            diagnostic["comparison_profile"]["comparison_period_count"],
            92,
        )
        self.assertEqual(
            diagnostic["comparison_profile"]["target_order"],
            [target.target_id for target in MODULE.TARGETS],
        )
        self.assertFalse(
            diagnostic["classification"]["standard_within_definition_revision"]
        )
        self.assertFalse(diagnostic["classification"]["truth_artifact"])
        self.assertFalse(diagnostic["classification"]["forecast_origin"])
        self.assertFalse(diagnostic["classification"]["score_artifact"])
        self.assertFalse(diagnostic["classification"]["accuracy_evidence"])
        self.assertEqual(
            diagnostic["classification"]["later_history_class"],
            "ANNUAL_UPDATE_REVISED_HISTORY",
        )
        self.assertEqual(len(diagnostic["source_bindings"]), 2)
        self.assertEqual(len(diagnostic["targets"]), 5)
        for binding in diagnostic["source_bindings"]:
            self.assertEqual(binding["gates"], MODULE.false_gates())
        for target in diagnostic["targets"]:
            self.assertEqual(target["gates"], MODULE.false_gates())
            self.assertEqual(len(target["level_revision"]["rows"]), 92)
            self.assertEqual(
                len(target["primary_transform_revision"]["rows"]),
                92,
            )
            self.assertEqual(
                target["level_revision"]["rows"][0]["period"],
                "1997Q1",
            )
            self.assertEqual(
                target["level_revision"]["rows"][-1]["period"],
                "2019Q4",
            )

    def test_official_regeneration_is_byte_identical_and_validated(self) -> None:
        diagnostic = MODULE.build_diagnostic(SOURCE_DIR)
        data = MODULE.canonical_json_bytes(diagnostic)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary).resolve() / "artifacts"
            first = MODULE.write_content_addressed(output, data)
            first_bytes = first.read_bytes()
            second = MODULE.write_content_addressed(output, data)
            self.assertEqual(first, second)
            self.assertEqual(first_bytes, second.read_bytes())
            validated = MODULE.validate_content_addressed(first, SOURCE_DIR)
            self.assertEqual(validated, diagnostic)
            self.assertEqual(
                first.name,
                (
                    "bea-hmi7-cross-archive-revision-diagnostic-sha256-"
                    f"{MODULE.sha256_bytes(data)}.json"
                ),
            )

    def test_checked_in_artifact_is_unique_and_exact(self) -> None:
        artifact_dir = MODULE_PATH.parent / "artifacts"
        artifacts = sorted(artifact_dir.glob("*.json"))
        self.assertEqual(len(artifacts), 1)
        validated = MODULE.validate_content_addressed(
            artifacts[0].resolve(),
            SOURCE_DIR,
        )
        expected = MODULE.build_diagnostic(SOURCE_DIR)
        self.assertEqual(validated, expected)

    def test_source_file_hash_tamper_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = copied_source_dir(Path(temporary))
            path = source / MODULE.SOURCES[0].filename
            path.write_bytes(path.read_bytes() + b" ")
            with self.assertRaisesRegex(MODULE.DiagnosticError, "SHA-256 drifted"):
                MODULE.load_pinned_sources(source)

    def test_source_filename_set_drift_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = copied_source_dir(Path(temporary))
            path = source / MODULE.SOURCES[0].filename
            path.rename(source / "renamed.json")
            with self.assertRaisesRegex(
                MODULE.DiagnosticError,
                "filenames are not exactly",
            ):
                MODULE.load_pinned_sources(source)

    def test_source_symlink_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "sources"
            source.mkdir()
            for spec in MODULE.SOURCES:
                (source / spec.filename).symlink_to(SOURCE_DIR / spec.filename)
            with self.assertRaisesRegex(MODULE.DiagnosticError, "path is unsafe"):
                MODULE.load_pinned_sources(source)
        with tempfile.TemporaryDirectory() as temporary:
            alias = Path(temporary) / "source-alias"
            alias.symlink_to(SOURCE_DIR, target_is_directory=True)
            with self.assertRaisesRegex(
                MODULE.DiagnosticError,
                "directory is unsafe",
            ):
                MODULE.load_pinned_sources(alias)

    def test_noncanonical_source_json_is_rejected(self) -> None:
        data = b'{\n  "value": 1\n}\n'
        with self.assertRaisesRegex(MODULE.DiagnosticError, "not canonical JSON"):
            MODULE.parse_canonical_json(data, "fixture")

    def test_duplicate_json_key_is_rejected(self) -> None:
        with self.assertRaisesRegex(MODULE.DiagnosticError, "duplicate JSON key"):
            MODULE.parse_canonical_json(b'{"value":1,"value":2}\n', "fixture")

    def test_true_source_gate_is_rejected(self) -> None:
        spec = MODULE.SOURCES[0]
        document = self.source_document(spec.role)
        document["artifact"]["gates"]["origin_admissible"] = True
        with self.assertRaisesRegex(MODULE.DiagnosticError, "hard-false gates"):
            MODULE.validate_source_document(document, spec)

    def test_missing_or_extra_source_gate_is_rejected(self) -> None:
        spec = MODULE.SOURCES[0]
        for mutation in ("missing", "extra"):
            with self.subTest(mutation=mutation):
                document = self.source_document(spec.role)
                gates = document["release"]["gates"]
                if mutation == "missing":
                    del gates["ready"]
                else:
                    gates["diagnostic_only"] = False
                with self.assertRaisesRegex(
                    MODULE.DiagnosticError,
                    "hard-false gates",
                ):
                    MODULE.validate_source_document(document, spec)

    def test_missing_or_reordered_period_is_rejected(self) -> None:
        spec = MODULE.SOURCES[0]
        for mutation in ("missing", "reordered"):
            with self.subTest(mutation=mutation):
                document = self.source_document(spec.role)
                target = mutate_target(document)
                observations = target["observations"]
                index = next(
                    index
                    for index, observation in enumerate(observations)
                    if observation["period"] == "2000Q1"
                )
                if mutation == "missing":
                    del observations[index]
                else:
                    observations[index], observations[index + 1] = (
                        observations[index + 1],
                        observations[index],
                    )
                with self.assertRaisesRegex(
                    MODULE.DiagnosticError,
                    "period axis drifted",
                ):
                    MODULE.validate_source_document(document, spec)

    def test_missing_or_extra_target_is_rejected(self) -> None:
        spec = MODULE.SOURCES[0]
        for mutation in ("missing", "extra"):
            with self.subTest(mutation=mutation):
                document = self.source_document(spec.role)
                targets = document["targets"]
                if mutation == "missing":
                    targets.pop()
                else:
                    extra = copy.deepcopy(targets[0])
                    extra["target_id"] = "unexpected_target"
                    targets.append(extra)
                with self.assertRaisesRegex(
                    MODULE.DiagnosticError,
                    "exactly the five pinned targets",
                ):
                    MODULE.validate_source_document(document, spec)

    def test_target_mapping_drift_is_rejected(self) -> None:
        spec = MODULE.SOURCES[0]
        document = self.source_document(spec.role)
        target = mutate_target(document, "core_pce_price_index")
        target["published_line_number"] = 24
        with self.assertRaisesRegex(MODULE.DiagnosticError, "line_number drifted"):
            MODULE.validate_source_document(document, spec)

    def test_nonpositive_comparison_value_is_rejected(self) -> None:
        spec = MODULE.SOURCES[0]
        for value in ("0", "-1"):
            with self.subTest(value=value):
                document = self.source_document(spec.role)
                target = mutate_target(document)
                observation = next(
                    observation
                    for observation in target["observations"]
                    if observation["period"] == "2000Q1"
                )
                observation["published_value_text"] = value
                with self.assertRaisesRegex(
                    MODULE.DiagnosticError,
                    "strictly positive|canonical nonnegative",
                ):
                    MODULE.validate_source_document(document, spec)

    def test_malformed_comparison_value_is_rejected(self) -> None:
        spec = MODULE.SOURCES[0]
        for value in ("NaN", "1e3", "+10", "01.0", "1,000"):
            with self.subTest(value=value):
                document = self.source_document(spec.role)
                target = mutate_target(document)
                observation = next(
                    observation
                    for observation in target["observations"]
                    if observation["period"] == "2000Q1"
                )
                observation["published_value_text"] = value
                with self.assertRaisesRegex(
                    MODULE.DiagnosticError,
                    "canonical nonnegative decimal",
                ):
                    MODULE.validate_source_document(document, spec)

    def test_raw_pair_or_release_profile_drift_is_rejected(self) -> None:
        spec = MODULE.SOURCES[1]
        for field in ("raw_pair_sha256", "release_profile_sha256"):
            with self.subTest(field=field):
                document = self.source_document(spec.role)
                document["release"][field] = "0" * 64
                with self.assertRaisesRegex(MODULE.DiagnosticError, f"{field} drifted"):
                    MODULE.validate_source_document(document, spec)

    def test_annual_update_classification_drift_is_rejected(self) -> None:
        spec = MODULE.SOURCES[1]
        document = self.source_document(spec.role)
        document["release"]["annual_update_caveat"] = (
            "NOT_AN_ANNUAL_UPDATE_RELEASE"
        )
        with self.assertRaisesRegex(
            MODULE.DiagnosticError,
            "annual_update_caveat drifted",
        ):
            MODULE.validate_source_document(document, spec)

    def test_mapping_or_parser_binding_drift_is_rejected(self) -> None:
        spec = MODULE.SOURCES[0]
        for field in ("mapping_profile_sha256", "parser_sha256"):
            with self.subTest(field=field):
                document = self.source_document(spec.role)
                document["artifact"][field] = "f" * 64
                with self.assertRaisesRegex(MODULE.DiagnosticError, f"{field} drifted"):
                    MODULE.validate_source_document(document, spec)

    def test_transform_uses_decimal_protocol_formula_and_fixed_lag(self) -> None:
        diagnostic = MODULE.build_diagnostic(SOURCE_DIR)
        nominal = next(
            target
            for target in diagnostic["targets"]
            if target["target_id"] == "nominal_gdp"
        )
        first = nominal["primary_transform_revision"]["rows"][0]
        self.assertEqual(first["period"], "1997Q1")
        self.assertEqual(
            nominal["primary_transform_revision"]["lag_support_period"],
            "1996Q4",
        )
        documents = self.documents
        earlier_values, _ = MODULE._source_target_values(
            documents[MODULE.SOURCES[0].role],
            "nominal_gdp",
        )
        with localcontext(MODULE._decimal_context()):
            expected = Decimal(400) * (
                Decimal(earlier_values["1997Q1"])
                / Decimal(earlier_values["1996Q4"])
            ).ln()
            expected_text = MODULE.decimal_text(+expected)
        self.assertEqual(first["earlier_transform"], expected_text)
        self.assertEqual(
            nominal["primary_transform_revision"]["summary"]["rmse_revision"],
            (
                "0.284099737279308765568699889140449280995226006153773350152481"
                "53428608019017876406"
            ),
        )

    def test_complete_row_hashes_match_rows(self) -> None:
        diagnostic = MODULE.build_diagnostic(SOURCE_DIR)
        for target in diagnostic["targets"]:
            for metric in ("level_revision", "primary_transform_revision"):
                rows = target[metric]["rows"]
                self.assertEqual(
                    target[metric]["rows_sha256"],
                    MODULE.sha256_bytes(MODULE.canonical_json_bytes(rows)),
                )

    def test_content_tamper_or_filename_drift_is_rejected(self) -> None:
        data = MODULE.canonical_json_bytes(MODULE.build_diagnostic(SOURCE_DIR))
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary).resolve() / "artifacts"
            path = MODULE.write_content_addressed(output, data)
            path.write_bytes(path.read_bytes()[:-1] + b" ")
            with self.assertRaisesRegex(
                MODULE.DiagnosticError,
                "filename hash does not match",
            ):
                MODULE.validate_content_addressed(path, SOURCE_DIR)

    def test_unsafe_or_relative_output_is_rejected(self) -> None:
        data = MODULE.canonical_json_bytes(MODULE.build_diagnostic(SOURCE_DIR))
        with self.assertRaisesRegex(
            MODULE.DiagnosticError,
            "must be absolute",
        ):
            MODULE.write_content_addressed(Path("relative"), data)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            destination = root / "linked-output"
            real = root / "real-output"
            real.mkdir()
            destination.symlink_to(real, target_is_directory=True)
            with self.assertRaisesRegex(MODULE.DiagnosticError, "unsafe"):
                MODULE.write_content_addressed(destination, data)

    def test_existing_nonfile_content_address_is_rejected(self) -> None:
        data = MODULE.canonical_json_bytes(MODULE.build_diagnostic(SOURCE_DIR))
        digest = MODULE.sha256_bytes(data)
        filename = (
            "bea-hmi7-cross-archive-revision-diagnostic-sha256-"
            f"{digest}.json"
        )
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary).resolve() / "artifacts"
            output.mkdir()
            (output / filename).mkdir()
            with self.assertRaisesRegex(MODULE.DiagnosticError, "unsafe"):
                MODULE.write_content_addressed(output, data)

    def test_dangling_content_address_symlink_is_not_replaced(self) -> None:
        data = MODULE.canonical_json_bytes(MODULE.build_diagnostic(SOURCE_DIR))
        digest = MODULE.sha256_bytes(data)
        filename = (
            "bea-hmi7-cross-archive-revision-diagnostic-sha256-"
            f"{digest}.json"
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            output = root / "artifacts"
            output.mkdir()
            destination = output / filename
            destination.symlink_to(root / "absent")
            with self.assertRaisesRegex(MODULE.DiagnosticError, "unsafe"):
                MODULE.write_content_addressed(output, data)
            self.assertTrue(destination.is_symlink())
            self.assertFalse(destination.exists())

    def test_empty_target_race_is_no_clobber(self) -> None:
        data = MODULE.canonical_json_bytes(MODULE.build_diagnostic(SOURCE_DIR))
        digest = MODULE.sha256_bytes(data)
        filename = (
            "bea-hmi7-cross-archive-revision-diagnostic-sha256-"
            f"{digest}.json"
        )
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary).resolve() / "artifacts"
            output.mkdir()
            destination = output / filename
            original_link = MODULE.os.link

            def racing_link(
                source: object,
                target: object,
                *args: object,
                **kwargs: object,
            ) -> None:
                Path(target).write_bytes(b"concurrent-content")
                original_link(source, target, *args, **kwargs)

            MODULE.os.link = racing_link
            try:
                with self.assertRaisesRegex(
                    MODULE.DiagnosticError,
                    "content differs",
                ):
                    MODULE.write_content_addressed(output, data)
            finally:
                MODULE.os.link = original_link
            self.assertEqual(destination.read_bytes(), b"concurrent-content")

    def test_temporary_source_swap_cannot_publish_successfully(self) -> None:
        data = MODULE.canonical_json_bytes(MODULE.build_diagnostic(SOURCE_DIR))
        digest = MODULE.sha256_bytes(data)
        filename = (
            "bea-hmi7-cross-archive-revision-diagnostic-sha256-"
            f"{digest}.json"
        )
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary).resolve() / "artifacts"
            output.mkdir()
            destination = output / filename
            original_link = MODULE.os.link
            displaced = output / "displaced-original"

            def swapping_link(
                source: object,
                target: object,
                *args: object,
                **kwargs: object,
            ) -> None:
                source_path = Path(source)
                source_path.rename(displaced)
                source_path.write_bytes(b"swapped-temporary-content")
                original_link(source, target, *args, **kwargs)

            MODULE.os.link = swapping_link
            try:
                with self.assertRaisesRegex(
                    MODULE.DiagnosticError,
                    "temporary diagnostic source changed",
                ):
                    MODULE.write_content_addressed(output, data)
            finally:
                MODULE.os.link = original_link
            self.assertTrue(destination.exists())
            self.assertNotEqual(destination.read_bytes(), data)
            self.assertNotEqual(MODULE.sha256_file(destination), digest)


if __name__ == "__main__":
    unittest.main(verbosity=2)
