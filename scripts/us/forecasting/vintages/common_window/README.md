# Offline common-origin-window decision

This directory freezes arithmetic and governance for the currently known
BEA, BLS, and EFFR source windows. It contains no network client, raw bytes,
parsed observation, truth value, forecast origin, score, or promotion result.
The artifact is a decision contract, not evidence that any source window is
complete or admissible.

## Frozen arithmetic

| Source window | Frozen range | Count |
|---|---:|---:|
| BEA HMI7 release metadata | 2011Q3--2021Q2 | 40 |
| BLS quarter-end archive metadata | 2015Q1--2024Q4 | 40 |
| clean post-break EFFR candidate | 2016Q2--2026Q1 | 40 |

The pairwise intersections are BEA/BLS 2015Q1--2021Q2 (26),
BEA/EFFR 2016Q2--2021Q2 (21), and BLS/EFFR 2016Q2--2024Q4 (35).
The exact all-three overlap is 2016Q2--2021Q2 (21), but its strict admitted
count is zero. The existence of 21 overlapping quarter labels does not prove
21 common-information-set forecast origins.

The separately recorded EFFR route-level range is 2016Q2--2026Q2 (41).
The fixed-40 research candidate ends at 2026Q1. At the 2026-08-07 freeze,
2026Q2 was already public and inspected, so the adjacent quarter is labeled
`ADJACENT_2026Q2_EVALUATION_RESERVE` with
`holdout_integrity = UNVERIFIED`. It is **not a prospective holdout**.
A genuinely prospective reserve can start no earlier than 2026Q3. The
identity 41 = fixed 40 + adjacent reserve is arithmetic only; it supplies no
holdout-integrity, origin-admission, or empirical-execution evidence. All
such gates remain false.

## Four non-interchangeable tracks

- `STRICT_FIRST_PUBLIC_BYTES` permits no empirical conclusion until exact
  first-public artifacts, availability, terms, truth, and origin gates pass.
- `OFFICIAL_ARCHIVE_RECONSTRUCTION` may support only a separately labeled
  research experiment after every declared gate passes. Official archive
  reconstruction is not first-public-byte evidence.
- `CURRENT_REVISED_PROXY` is limited to descriptive revised-data
  diagnostics. The New York Fed API and current Board H.15 series are current
  state, not historical vintages.
- `MIXED_CONCEPT_AND_PROVENANCE_SENSITIVITY` is a disclosed sensitivity only.
  Pre-2016 EFFR uses a different concept and must retain `CONCEPT_BREAK`.

The candidate ALFRED route is `DATE_LEVEL_VINTAGE`, but its terms state is
`TERMS_LOCAL_GOVERNANCE_BLOCKED_PENDING_REVIEW`. FRASER OCR may locate H.15
issues but remains `OCR_NOT_AUTHORITATIVE`. Bare `Used` and `Other` are
invalid source, provenance, concept, blocker, and decision labels.

## Irregularities retained as types

The contract preserves:

- BEA 2018Q4 `INITIAL_REPLACES_ADVANCE_AND_SECOND`;
- BLS 2019Q4 `REISSUED_CORRECTED`;
- BLS 2025Q3 `DELAYED_BY_FEDERAL_LAPSE`;
- BEA 2025Q3 `INITIAL_REPLACES_ADVANCE_AND_SECOND`, after the Advance and
  Second estimates were canceled; and
- BLS October 2025 `SKIPPED_NOT_PUBLISHED_NON_PANEL_MONTH`.

The last item is a monthly non-event and is not counted as a quarter-end
panel event. None of these records is admitted.

## Evidence basis

Official source documentation:

- [BEA HMI7 archive](https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/?HistMainId=7&getFiles=false&getDirs=true)
- [BLS Employment Situation archive](https://www.bls.gov/bls/news-release/empsit.htm)
- [BLS December 2019 reissued release](https://www.bls.gov/news.release/archives/empsit_01102020.htm)
- [BLS 2025 shutdown impact on CPS](https://www.bls.gov/cps/methods/2025-federal-government-shutdown-impact-cps.htm)
- [BLS September 2025 delayed release](https://www.bls.gov/news.release/archives/empsit_11202025.htm)
- [BEA 2025Q3 Initial estimate](https://www.bea.gov/news/2025/gross-domestic-product-3rd-quarter-2025-initial-estimate-and-corporate-profits)
- [BEA schedule explanation](https://www.bea.gov/news/blog/2025-12-10/economic-release-schedule-updates)
- [New York Fed EFFR description](https://www.newyorkfed.org/markets/reference-rates/effr)
- [New York Fed methodology and revisions](https://www.newyorkfed.org/markets/reference-rates/additional-information-about-reference-rates)
- [Federal Reserve Board H.15](https://www.federalreserve.gov/releases/h15/)
- [FRASER H.15 archive](https://fraser.stlouisfed.org/title/h15-selected-interest-rates-86)
- [FRED terms](https://fred.stlouisfed.org/legal/terms/) and
  [API terms](https://fred.stlouisfed.org/docs/api/terms_of_use.html)

The research boundary follows Croushore and Stark,
[*A Real-Time Data Set for Macroeconomists*](https://doi.org/10.1016/S0304-4076(01)00072-0);
Koenig, Dolmas, and Piger,
[*The Use and Abuse of Real-Time Data in Economic Forecasting*](https://doi.org/10.1162/003465303322369768);
and Fett,
[*Comparing with the original*](https://doi.org/10.21916/mlr.2015.12).

## Verification

Run from the repository root:

```sh
julia --startup-file=no --project=scripts/us --check-bounds=yes \
  --depwarn=error \
  scripts/us/forecasting/vintages/common_window/test_common_origin_window_decision.jl
```

The TOML content has a typed, length-aware semantic digest excluding only
its own `artifact.content_sha256` field. Validation also requires a compiled
digest pin. Trusted returns contain only immutable named tuples, tuples, and
scalar values. There is deliberately no stamping helper.
