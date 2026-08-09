#!/usr/bin/env python3
"""Offline tests for the quarantined revised-data panel fixture."""

from __future__ import annotations

import csv
import json
import math
import re
import shutil
import tempfile
import tomllib
import unittest
from collections import defaultdict
from datetime import date
from pathlib import Path

from build_fixture import BuildError, normalized_effr
from revised_panel import (
    BEA_SOURCE_PATH,
    BLS_SOURCE_PATH,
    EFFR_SOURCE_PATH,
    EXPECTED_BEA_FINGERPRINT_SHA256,
    EXPECTED_END_PERIOD,
    EXPECTED_MANIFEST_SHA256,
    EXPECTED_ROW_COUNT,
    EXPECTED_START_PERIOD,
    FIXTURE_DIR,
    MANIFEST_PATH,
    PANEL_COLUMNS,
    PANEL_PATH,
    RECEIPT_PATH,
    RevisedPanelError,
    derive_panel_bytes,
    load_bls_levels,
    load_effr_rates,
    period_from_date,
    sha256_file,
    verify_fixture,
)

EXPECTED_HASHES = {
    "manifest.toml": (
        "fc5209e35bb0d04986c2f8c96563f0c21ad511680753ecc7e6d77f0d8435fb3f"
    ),
    "quarterly_panel.csv": (
        "f7bb26a467465937060b1e9e734a020b9158a8136db05d2e0df47c3bff851bbe"
    ),
    "source_receipts.json": (
        "14bab08bb573265e0affc878cedbbb8d4a0f8f5510fc59990f92d614f109d488"
    ),
    "bea_quarterly_levels.csv": (
        "977f85676b087eba896847895a3c4c9c88976c30d10d99f582fe62598ae8f158"
    ),
    "bls_monthly_levels.csv": (
        "9100125a88e928f8e03bcfb78a0c71efe45fc0b16c3ce816422de2a6a709ea28"
    ),
    "effr_daily_rates.csv": (
        "77a1ef7ca350c937562d97586a3ae33b09d6da2006d5c1bad644ec3b0911384b"
    ),
}
EXPECTED_RAW_HASHES = {
    "bls_public_api_v2_2000_2009": (
        "6c81373f7717e0bf4a397d5bf44e351ed9c5d4d888d32fea4c0959598fb4b7e4"
    ),
    "bls_public_api_v2_2010_2019": (
        "71578257fffc6af1719e96b44e41d0177c8af64eb4364e989942eaaf4719c534"
    ),
    "bls_public_api_v2_2020_2026": (
        "5cb13733d8ead584261d69b3e8aa106888a294cd741beb1fbb4b0e0bc293d4af"
    ),
    "new_york_fed_effr_current_revised_snapshot": (
        "193853c9798f56568298a89f97263a83ef9f0d30840f486fd6d7d2334e3a18de"
    ),
}


def csv_records(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


class RevisedPanelFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = tomllib.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        cls.receipt = json.loads(RECEIPT_PATH.read_bytes())
        cls.panel = csv_records(PANEL_PATH)
        cls.panel_by_period = {row["period"]: row for row in cls.panel}
        cls.bea = csv_records(BEA_SOURCE_PATH)
        cls.bls = csv_records(BLS_SOURCE_PATH)
        cls.effr = csv_records(EFFR_SOURCE_PATH)

    def test_full_fixture_verification(self) -> None:
        result = verify_fixture()
        self.assertEqual(result.manifest_sha256, EXPECTED_MANIFEST_SHA256)
        self.assertEqual(result.panel_sha256, EXPECTED_HASHES["quarterly_panel.csv"])
        self.assertEqual(result.receipt_sha256, EXPECTED_HASHES["source_receipts.json"])
        self.assertEqual(result.row_count, EXPECTED_ROW_COUNT)
        self.assertEqual(result.start_period, EXPECTED_START_PERIOD)
        self.assertEqual(result.end_period, EXPECTED_END_PERIOD)
        self.assertEqual(result.effr_observation_count, 6530)

    def test_all_tracked_fixture_hashes_are_pinned(self) -> None:
        for filename, expected in EXPECTED_HASHES.items():
            with self.subTest(filename=filename):
                self.assertEqual(sha256_file(FIXTURE_DIR / filename), expected)

    def test_primary_panel_contract_and_complete_case_boundary(self) -> None:
        self.assertEqual(tuple(self.panel[0]), PANEL_COLUMNS)
        self.assertEqual(len(self.panel), 101)
        self.assertEqual(self.panel[0]["period"], "2000Q3")
        self.assertEqual(self.panel[-1]["period"], "2025Q3")
        self.assertNotIn("2025Q4", self.panel_by_period)
        self.assertNotIn("2026Q1", self.panel_by_period)
        self.assertEqual(self.manifest["row_count"], 101)
        self.assertEqual(self.manifest["start_period"], "2000Q3")
        self.assertEqual(self.manifest["end_period"], "2025Q3")
        boundary = self.manifest["complete_case_boundary"]
        self.assertEqual(boundary["first_excluded_period"], "2025Q4")
        self.assertEqual(
            boundary["missing_source_observation"], "LNS14000000 2025-10"
        )
        self.assertFalse(boundary["two_month_mean_used"])
        self.assertFalse(boundary["missing_value_imputed"])
        self.assertTrue(boundary["post_gap_source_observations_retained"])
        self.assertEqual(boundary["post_gap_source_end_period"], "2026Q2")
        self.assertEqual(
            boundary["official_guidance_url"],
            (
                "https://www.bls.gov/cps/methods/"
                "2025-federal-government-shutdown-impact-cps.htm"
            ),
        )

    def test_quarantine_flags_fail_closed(self) -> None:
        for artifact in (self.manifest, self.receipt):
            self.assertEqual(
                artifact["information_track"],
                "revised_mixed_vintage_diagnostic",
            )
            self.assertFalse(artifact["forecast_origin_admissible"])
            self.assertFalse(artifact["promotion_eligible"])
            self.assertFalse(artifact["abm_accuracy_claimed"])
            self.assertFalse(artifact["bitemporal"])
            self.assertFalse(artifact["real_time"])
            self.assertTrue(artifact["revised_current_release_snapshot"])
        quarantine = self.manifest["quarantine"]
        self.assertFalse(quarantine["historical_release_availability_verified"])
        self.assertFalse(quarantine["first_release_truth"])
        self.assertFalse(quarantine["near_mature_truth"])
        self.assertFalse(quarantine["mature_truth"])
        self.assertFalse(quarantine["inventory_registered"])
        self.assertEqual(quarantine["origin_count_added"], 0)
        self.assertEqual(quarantine["abm_forecast_scores_added"], 0)

    def test_source_extract_counts_and_boundaries(self) -> None:
        self.assertEqual(len(self.bea), 525)
        self.assertEqual(len(self.bls), 636)
        self.assertEqual(len(self.effr), 6530)
        self.assertEqual(self.bea[0]["period"], "2000Q2")
        self.assertEqual(self.bea[-1]["period"], "2026Q2")
        self.assertEqual(self.bls[0]["month"], "2000-01")
        self.assertEqual(self.bls[-1]["month"], "2026-06")
        self.assertEqual(self.effr[0]["effective_date"], "2000-07-03")
        self.assertEqual(self.effr[-1]["effective_date"], "2026-06-30")
        self.assertEqual(
            self.receipt["bea_content_fingerprint_sha256"],
            EXPECTED_BEA_FINGERPRINT_SHA256,
        )
        self.assertEqual(
            self.receipt["sources"]["bea"]["observation_count"], 525
        )
        self.assertEqual(
            self.receipt["sources"]["bls"]["observation_count"], 636
        )
        self.assertEqual(
            self.receipt["sources"]["new_york_fed_effr"]["observation_count"],
            6530,
        )

    def test_bls_raw_receipts_have_exact_request_and_response_evidence(self) -> None:
        responses = self.receipt["sources"]["bls"]["responses"]
        self.assertEqual(len(responses), 3)
        expected_windows = (("2000", "2009"), ("2010", "2019"), ("2020", "2026"))
        for response, (start, end) in zip(responses, expected_windows):
            source_id = response["source_id"]
            self.assertEqual(response["raw_sha256"], EXPECTED_RAW_HASHES[source_id])
            self.assertEqual(
                response["requested_url"],
                "https://api.bls.gov/publicAPI/v2/timeseries/data/",
            )
            self.assertEqual(response["effective_url"], response["requested_url"])
            self.assertEqual(response["method"], "POST")
            self.assertEqual(response["http_status"], 200)
            self.assertEqual(response["requested_start_year"], start)
            self.assertEqual(response["requested_end_year"], end)
            self.assertEqual(
                response["series_ids"],
                ["CES0000000001", "LNS14000000"],
            )
            self.assertRegex(
                response["acquisition_started_at_utc"],
                r"^2026-08-06T[0-9:.]+Z$",
            )
            self.assertRegex(
                response["acquisition_completed_at_utc"],
                r"^2026-08-06T[0-9:.]+Z$",
            )
            headers = response["selected_response_headers"]
            self.assertEqual(headers["content-type"], "application/json")
            self.assertEqual(int(headers["content-length"]), response["raw_byte_count"])
            self.assertIn("date", headers)
            for series_id in ("CES0000000001", "LNS14000000"):
                expected_count = 78 if start == "2020" else 120
                self.assertEqual(
                    response["observation_counts"][series_id],
                    expected_count,
                )
                self.assertEqual(
                    response["observation_bounds"][series_id]["first_month"],
                    f"{start}-01",
                )
                expected_last = "2026-06" if start == "2020" else f"{end}-12"
                self.assertEqual(
                    response["observation_bounds"][series_id]["last_month"],
                    expected_last,
                )
            self.assertFalse(response["raw_bytes_checked_into_git"])

    def test_official_bls_gap_is_preserved_and_not_aggregated(self) -> None:
        missing = [
            row
            for row in self.bls
            if row["series_id"] == "LNS14000000"
            and row["published_value"] == "-"
        ]
        self.assertEqual(
            missing,
            [
                {
                    "month": "2025-10",
                    "series_id": "LNS14000000",
                    "published_value": "-",
                    "latest": "false",
                    "footnote_codes": "9",
                }
            ],
        )
        missing_receipt = self.receipt["sources"]["bls"][
            "unavailable_observations"
        ]
        self.assertEqual(len(missing_receipt), 1)
        self.assertEqual(missing_receipt[0]["month"], "2025-10")
        self.assertIn(
            "lapse in appropriations",
            missing_receipt[0]["footnote_texts"][0],
        )
        levels = load_bls_levels()
        self.assertIsNone(levels["LNS14000000"]["2025-10"])
        transform = self.manifest["transformations"]["unemployment_rate"]
        self.assertFalse(transform["two_month_mean_used"])
        self.assertFalse(transform["missing_month_values_imputed"])
        self.assertIn("stops at 2025Q3", transform["missing_month_boundary"])

    def test_national_accounts_transform_is_independently_recomputed(self) -> None:
        levels = {
            (row["target_id"], row["period"]): float(row["published_value"])
            for row in self.bea
        }
        for target in (
            "real_gdp",
            "pce_price_index",
            "core_pce_price_index",
            "gdp_deflator",
            "nominal_gdp",
        ):
            expected = 400.0 * math.log(
                levels[(target, "2000Q3")] / levels[(target, "2000Q2")]
            )
            self.assertAlmostEqual(
                float(self.panel_by_period["2000Q3"][target]),
                expected,
                places=10,
            )

    def test_bls_quarterly_transforms_are_independently_recomputed(self) -> None:
        levels = {
            (row["series_id"], row["month"]): float(row["published_value"])
            for row in self.bls
            if row["published_value"] != "-"
        }
        payroll_q2 = sum(
            levels[("CES0000000001", f"2000-{month:02d}")]
            for month in (4, 5, 6)
        ) / 3.0
        payroll_q3 = sum(
            levels[("CES0000000001", f"2000-{month:02d}")]
            for month in (7, 8, 9)
        ) / 3.0
        expected_payroll = 100.0 * math.log(payroll_q3 / payroll_q2)
        expected_unemployment = sum(
            levels[("LNS14000000", f"2000-{month:02d}")]
            for month in (7, 8, 9)
        ) / 3.0
        observed = self.panel_by_period["2000Q3"]
        self.assertAlmostEqual(
            float(observed["payroll_employment"]),
            expected_payroll,
            places=10,
        )
        self.assertAlmostEqual(
            float(observed["unemployment_rate"]),
            expected_unemployment,
            places=10,
        )

    def test_effr_business_date_rule_and_transform(self) -> None:
        rates = load_effr_rates()
        self.assertEqual(len(rates), 6530)
        self.assertTrue(all(effective.weekday() < 5 for effective in rates))
        grouped = defaultdict(list)
        for effective, rate in rates.items():
            grouped[period_from_date(effective)].append(float(rate))
        expected = sum(grouped["2000Q3"]) / len(grouped["2000Q3"])
        self.assertAlmostEqual(
            float(
                self.panel_by_period["2000Q3"][
                    "effective_federal_funds_rate"
                ]
            ),
            expected,
            places=10,
        )
        effr_receipt = self.receipt["sources"]["new_york_fed_effr"]
        self.assertEqual(
            effr_receipt["raw_sha256"],
            EXPECTED_RAW_HASHES["new_york_fed_effr_current_revised_snapshot"],
        )
        self.assertEqual(effr_receipt["raw_observation_count"], 6531)
        self.assertEqual(effr_receipt["excluded_nonbusiness_observation_count"], 1)
        self.assertEqual(
            effr_receipt["excluded_nonbusiness_observations"],
            [
                {
                    "effective_date": "2003-07-20",
                    "identical_fields_excluding_effective_date": True,
                    "matching_effective_date": "2003-07-21",
                    "matching_rate_percent": "1.02",
                    "paired_published_fields_sha256": (
                        "22ad04b714f9c4ec793193afaee04d1e35ee81ca6af51c8faec61e67"
                        "f776ddf9"
                    ),
                    "rate_percent": "1.02",
                    "rule": (
                        "excluded_exact_known_duplicate_without_reassignment"
                    ),
                    "weekday": "Sunday",
                }
            ],
        )
        self.assertNotIn(date(2003, 7, 20), rates)
        self.assertFalse(effr_receipt["weekend_observations_imputed"])

    @staticmethod
    def write_synthetic_effr_raw(
        raw_dir: Path,
        rows: list[dict[str, str]],
    ) -> dict[str, object]:
        raw_dir.mkdir(parents=True)
        path = raw_dir / "effr_2000-07-01_2026-06-30.csv"
        with path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(
                stream,
                fieldnames=[
                    "Effective Date",
                    "Rate Type",
                    "Rate (%)",
                    "Revision Indicator (Y/N)",
                ],
                lineterminator="\n",
            )
            writer.writeheader()
            writer.writerows(rows)
        return {
            "acquisitions": [
                {
                    "source_id": "new_york_fed_effr_20000701_20260630",
                }
            ]
        }

    def test_arbitrary_weekend_effr_row_is_rejected(self) -> None:
        matching_fields = {
            "Rate Type": "EFFR",
            "Rate (%)": "1.02",
            "Revision Indicator (Y/N)": "",
        }
        with tempfile.TemporaryDirectory() as temporary:
            raw_dir = Path(temporary) / "raw"
            receipt = self.write_synthetic_effr_raw(
                raw_dir,
                [
                    {"Effective Date": "07/21/2003", **matching_fields},
                    {"Effective Date": "07/20/2003", **matching_fields},
                    {"Effective Date": "07/19/2003", **matching_fields},
                ],
            )
            with self.assertRaisesRegex(
                BuildError,
                "unexpected nonbusiness-date EFFR row 2003-07-19",
            ):
                normalized_effr(raw_dir, receipt)

    def test_nonmatching_sunday_monday_effr_pair_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            raw_dir = Path(temporary) / "raw"
            receipt = self.write_synthetic_effr_raw(
                raw_dir,
                [
                    {
                        "Effective Date": "07/21/2003",
                        "Rate Type": "EFFR",
                        "Rate (%)": "1.02",
                        "Revision Indicator (Y/N)": "Y",
                    },
                    {
                        "Effective Date": "07/20/2003",
                        "Rate Type": "EFFR",
                        "Rate (%)": "1.02",
                        "Revision Indicator (Y/N)": "",
                    },
                ],
            )
            with self.assertRaisesRegex(
                BuildError,
                "does not exactly duplicate Monday fields",
            ):
                normalized_effr(raw_dir, receipt)

    def test_missing_monday_effr_pair_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            raw_dir = Path(temporary) / "raw"
            receipt = self.write_synthetic_effr_raw(
                raw_dir,
                [
                    {
                        "Effective Date": "07/20/2003",
                        "Rate Type": "EFFR",
                        "Rate (%)": "1.02",
                        "Revision Indicator (Y/N)": "",
                    }
                ],
            )
            with self.assertRaisesRegex(
                BuildError,
                "no adjacent Monday match",
            ):
                normalized_effr(raw_dir, receipt)

    def test_new_york_fed_notice_and_attribution_are_preserved(self) -> None:
        terms = self.manifest["source_terms"]["new_york_fed"]
        self.assertIn("© 2026 Federal Reserve Bank of New York", terms["attribution"])
        self.assertIn(
            "subject to the Terms of Use posted at newyorkfed.org",
            terms["reference_rate_notice"],
        )
        self.assertIn("Modified/derived by BeforeIT", terms["modification_notice"])
        self.assertEqual(
            terms["terms_url"],
            "https://www.newyorkfed.org/privacy/termsofuse",
        )
        self.assertEqual(
            terms["source_page_url"],
            "https://www.newyorkfed.org/markets/reference-rates/effr",
        )

    def test_panel_has_no_missing_or_nonfinite_values(self) -> None:
        for row in self.panel:
            self.assertEqual(set(row), set(PANEL_COLUMNS))
            for target in PANEL_COLUMNS[1:]:
                self.assertNotEqual(row[target], "")
                self.assertTrue(math.isfinite(float(row[target])))

    def test_offline_rebuild_is_byte_identical(self) -> None:
        self.assertEqual(derive_panel_bytes(), PANEL_PATH.read_bytes())

    def test_panel_mutation_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary) / "fixtures"
            shutil.copytree(FIXTURE_DIR, fixture)
            panel_path = fixture / "quarterly_panel.csv"
            panel_path.write_text(
                panel_path.read_text(encoding="utf-8").replace(
                    "2000Q3,", "2000Q3,999,"
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RevisedPanelError, "panel SHA-256"):
                verify_fixture(fixture, enforce_manifest_pin=False)

    def test_promotion_flag_mutation_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary) / "fixtures"
            shutil.copytree(FIXTURE_DIR, fixture)
            manifest_path = fixture / "manifest.toml"
            manifest_path.write_text(
                manifest_path.read_text(encoding="utf-8").replace(
                    "promotion_eligible = false",
                    "promotion_eligible = true",
                    1,
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                RevisedPanelError, "promotion_eligible must be false"
            ):
                verify_fixture(fixture, enforce_manifest_pin=False)

    def test_manifest_pin_mutation_is_rejected_before_parsing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary) / "fixtures"
            shutil.copytree(FIXTURE_DIR, fixture)
            manifest_path = fixture / "manifest.toml"
            manifest_path.write_bytes(manifest_path.read_bytes() + b"\n")
            with self.assertRaisesRegex(RevisedPanelError, "compiled fixture pin"):
                verify_fixture(fixture)


if __name__ == "__main__":
    unittest.main(verbosity=2)
