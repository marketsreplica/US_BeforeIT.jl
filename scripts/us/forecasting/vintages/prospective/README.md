# Prospective 2026Q3 acquisition contract

This directory defines a draft, fail-closed successor surface for prospective
source acquisition. It does not replace the v1 source-release registry, alter
`current_inventory.toml`, install source bytes, approve requirements, admit an
origin, or make a forecast runnable.

The original `prospective_2026q3_contract.toml` and
`USProspectiveAcquisitionContract.jl` remain the v1 historical contract. The
additive `prospective_2026q3_contract_v2.toml` and
`USProspectiveAcquisitionContractV2.jl` close a selector-completeness gap
without changing v1 semantics.

## Selector-complete v2 plan

V1 identifies 11 source-family routes. A receipt for a route can prove the
availability of exact bytes, but the route alone cannot prove that every table,
series, concordance, or inventory stage needed by calibration was captured.
V2 therefore splits the acquisition surface into 21 atomic requirements and 107
planned artifact profiles. Every requirement uses
`completion_rule = "ALL_PROFILES_VERIFIED"` and pins the exact selector for
each profile. The
`beforeit-us-prospective-acquisition-requirements.v6-draft` artifact is
canonically hash-bound under
`utf8-length-prefixed-sorted-map-array-order.v1` with SHA-256:

```text
5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a
```

Every evidence row must carry a canonical
`beforeit-us-resolved-selector-evidence.v3-draft` record. That record resolves
the planned selector to a concrete release, reference period, dataset,
frequency, table, line, series, workbook member, and official artifact
locator; it also binds the eligible-candidate catalog and rank, raw and
receipt hashes, and receipt completion time. Its canonical hash must equal the
row's `selector_evidence_sha256`. A resolved-dimensions map must contain every
key in the policy selector. Fixed values such as year, release, sheet,
geography, price basis, and required-field lists must match exactly; symbolic
values cannot be narrowed to one convenient member. Each dynamic key has a
typed `set_resolutions` record binding its policy value, coverage mode, member
count, membership SHA-256, `sha256:<members_sha256>` resolved value, and the
same candidate-catalog hash as the parent record. Full histories and published
universes require at least two claimed members; only a latest-eligible
selection may claim one. Artifact URLs must use a host allowed for the
selector's source, so a globally official Census or GitHub host cannot satisfy
a BEA selector. Project artifacts are additionally restricted to
`marketsreplica/US_BeforeIT.jl`; route and schedule pages remain invalid.

`evaluate_requirement_completion` accepts evidence only when its requirement,
profile, selector, exact profile-authorized capture, resolution record, hashes,
conservative availability upper bound, receipt status, durable storage, and
retention boundary all match. Each requirement has a default capture and,
where needed, profile-specific capture overrides and terminal coverage dates.
Event-level authorization alone cannot substitute a rehearsal, stale
structural snapshot, wrong release, premature EFFR manifest, or holiday row
for the profile's required capture.

Even synthetically supplying all profiles can establish only
`shape_complete=true`. It never produces `complete=true` while the independent
verifier remains `NOT_IMPLEMENTED_FAIL_CLOSED`; `verifier_attested`,
`origin_admissible`, `ready`, and `inventory_mutation_authorized` stay hard
false. The checked-in contract has zero registered raw artifacts, zero
receipts, zero admitted origins, and no forecast or accuracy evidence.
`shape_complete` proves schema, selector, capture, and hash-binding shape only;
the independent verifier must still check the claimed catalog, set members,
and artifact bytes.

### Planned source coverage

The 107 profiles now include selector-level acquisition obligations for:

- BEA NIPA T10105 lines 1, 2, 7, 8, 14, 16, 19, and 22, and T10106 lines 1,
  2, 8, 16, 19, and 22, with signed-flow, SAAR, and chained-dollar semantics;
  complete 2024 T11000/T11200/T11400 and T30100/T30200/T30300 tables,
  selected household, contribution, benefit, capital-tax, and interest lines,
  T10103 line 8, and monthly T20600 line 3 / BEA series `A034RC`;
- separately hashable annual-2024 and quarterly-through-2026Q2
  GDP-by-industry profiles for Tables 1, 10, 15, 20, 208, and 209, plus annual
  Table 6, with the published industry universe resolved at capture;
- the complete 2026Q2 Z.1 release CSV bundle, matching series dictionary, code
  changes/table map, and exact quarterly series `FL104000005.Q`,
  `FL114000005.Q`, `FL144104005.Q`, `FL154000005.Q`, `FL214104005.Q`,
  `FL314104005.Q`, `FL704190005.Q`, and `FL704194005.Q`;
- a monthly `FEDFUNDS` calibration history from October 1996 through September
  2026, distinct from the prospective daily EFFR target receipts;
- exact 2023 AIES ZIP and pipe-delimited `.dat` members at national geography
  and 2017 NAICS: AIES00 receipts and total-inventory values, flags, CV, and
  CV flags; AIES31/42/44 total, LIFO, and LIFO-reserve values with their flags,
  CV, and CV flags; and AIES51 total, finished, work-in-process, and materials
  values with their flags, CV, and CV flags; QCEW 2022/2024 annual national
  files plus the 2026Q1 release; and all published enterprise-size rows in the
  2022 SUSB U.S. six-digit-NAICS file;
- the MRTS `mrtsinv92-present.xlsx` end-of-month inventory and
  inventory-to-sales-ratio workbook, in millions of current dollars without
  price adjustment, with both SA and NSA full kind-of-business rows; the MWTS
  `timeseries1.xlsx` seasonally/trading-day-adjusted and `timeseries2.xlsx`
  not-adjusted workbooks, both for merchant wholesalers excluding
  manufacturers' sales branches and offices and the full published rows;
- official BEA code lists covering 71 source industries, 71 source
  commodities, `Other`, and `Used`; the October 2023
  `BEA-Industry-and-Commodity-Codes-and-NAICS-Concordance.xlsx`; the NAICS 2017
  and 2022 structures and concordance; and the repository `bea71.toml` model
  bridge pinned to SHA-256
  `2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f`;
  and
- actual valuation-source inputs: 2024 after-redefinitions producer-price use
  and make workbooks, the 2024 imports-by-user matrix, and both purchaser- and
  producer-price 2017 benchmark use tables, alongside complete Table 259 and
  Table 262 axes and controls.

This is acquisition-shape coverage, not an implemented economic bridge. The
profiles do not supply the missing 2017-to-2024 cell-level valuation
allocation and uncertainty bridge, inventory holder-to-sector/commodity and
stage-to-model-stock-scope bridges, a full Z.1 instrument/counterparty bridge,
the derived 71-to-68 model reconciliation, the independent evidence verifier,
requirements approval, accounting promotion, origin admission, or forecast
readiness. The executable pipeline also needs a versioned migration from its
FRED aliases for Z.1 and wages to the primary source receipts named here.

V2 expands the existing BEA and BLS event bindings, adds exact official Census
captures for:

- August 2026 M3 full report at `2026-10-02T14:00:00Z`;
- both August 2026 MWTS workbooks at `2026-10-08T14:00:00Z`;
- August 2026 MRTS inventories at `2026-10-15T14:00:00Z`; and
- September 2026 M3 advance report at `2026-10-27T12:30:00Z`.

It also adds `final_structural_pre_origin`, bounded from
`2026-10-29T13:30:00Z` through `2026-10-30T13:45:00Z`, to prove the last
eligible structural bytes after the advance-GDP release and before the
`2026-10-30T14:00:00Z` origin. These entries are requirements, not captured
evidence: their receipt counts remain zero and origin eligibility remains
false.

The named 2025 after-redefinitions valuation archive is assigned to the early
August snapshot campaign so it cannot be silently replaced by the mutable ZIP
after the September 2026 annual update. The annual-update event is retained as
a non-completeness rehearsal; evidence is accepted only from each profile's
explicit capture.

`prospective_2026q3_contract_v2.toml` keeps three questions separate:

1. Can exact bytes be conservatively proven available before the origin?
2. Is the cross-artifact verifier implemented and able to verify receipts?
3. Has the requirements artifact been approved by distinct model-owner and
   independent-validator identities?

A temporal evidence candidate cannot activate the contract unless both
governance questions also pass. The checked-in states are
`NOT_IMPLEMENTED_FAIL_CLOSED` and `DRAFT_UNAPPROVED`, so the candidate origin
remains `PLANNED_NOT_CAPTURED_NOT_ADMITTED`.

## Conservative prospective availability

The draft field `availability_upper_bound_utc` is not an inferred or asserted
original publication time. It is the exact completion time of a verified
receipt proving that the receipt-bound bytes were accessible no later than
that time. The upper bound must:

- equal `receipt_completed_at_utc`;
- be strictly before `2026-10-30T14:00:00Z`;
- fall within the contract's fixed, recurring, or snapshot capture window;
- bind raw and receipt SHA-256 identities;
- have verified durable storage; and
- be retained through at least the 60-month mature-truth horizon.

This rule is prospective only. A post-origin retrieval cannot reconstruct a
historical information set. A route, mutable schedule page, unverified receipt,
or short-retention CI artifact is not availability evidence.

The policy is deliberately isolated from the v1 rule that requires an exact
original release timestamp. Activating it later requires a versioned registry
transition and evidence verifier; this draft does not silently reinterpret v1
fields.

## Pinned capture calendar

The fixed calendar records the audited BLS Employment Situation rehearsals,
August QCEW release, September Z.1 release, BEA annual-update rehearsal, last
pre-origin Employment Situation, October 29 advance-GDP trigger, and the approximately
09:00 ET EFFR publication one hour before the origin cutoff. Separate recurring
windows preserve the approximately 09:00 ET first-state and 14:30 ET same-day
revision checks. Slow-moving fixed-assets, the pinned 2025 valuation archive,
CPS, SUSB, classification, and USDA files have a pre-origin snapshot campaign bounded from
`2026-08-06T00:00:00Z` through `2026-08-31T23:59:59Z`; older receipts cannot be
reclassified as prospective evidence.

All entries remain `PLANNED_NOT_CAPTURED`, have zero receipts, and are
origin-ineligible. The calendar is an acquisition requirement, not evidence
that any release occurred or that its bytes were captured.

## Retention boundary

Raw bytes and receipt bytes must be content-addressed, co-retained in at least
two durable write-once or versioned copies, and covered by an external timestamp
receipt and hash manifest through at least
`2031-10-30T14:00:00Z`. A 30-day GitHub Actions artifact alone is explicitly
insufficient.

Run the hermetic contract tests with:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/prospective/test_prospective_acquisition_contract.jl

julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/prospective/test_prospective_acquisition_contract_v2.jl
```

The v1 suite remains an independent compatibility contract. The 355-test v2
suite exercises the checked-in closed state, exact source-profile inventory,
canonical resolution hashes, profile/capture binding, conservative pre-origin
evidence candidates, the fixed and recurring calendar, retention, and
adversarial post-origin, wrong-capture, unresolved-selector, schedule-only,
cross-source-host, singleton-narrowing, unverified, short-lived, and tampered
cases. Synthetic in-memory evidence and governance transitions are test
fixtures only; they do not install receipts, implement the verifier, approve
the checked-in artifact, admit an origin, or make a forecast ready.
