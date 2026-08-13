# U.S. Tier-1 target and truth coverage

This directory is the WS-0A/WS-1A boundary for the eight Tier-1 forecast
targets frozen in `../protocol.toml`. It defines the exact official target,
the source-frequency-to-quarterly transformation, the observation-operator
version, and the three truth layers that must exist before a forecast score
can be promotion evidence.

Files:

- `tier1_targets.toml` is the hash-addressed coverage inventory.
- `USTier1TargetCoverage.jl` validates the schema, source concepts, weights,
  vintage labels, truth layers, and promotion gate.
- `test_target_coverage.jl` is a hermetic positive and negative test suite.
- `abm_gdp_operator/` is a synthetic-only arithmetic qualification for the
  unapproved real-GDP-growth and GDP-deflator-inflation candidates.

## Current audited result

The installed repository is **not promotion ready**:

| Coverage item | Count | Interpretation |
|---|---:|---|
| Required Tier-1 targets | 8 | Exact protocol set; weights sum to 1 |
| Approximately installed | 4 | Real GDP, a derived GDP-deflator ratio, CPS unemployment, and nominal GDP |
| Exact promotion-ready targets | 0 | Approximate/current-vintage material is not exact frozen target coverage |
| Absent targets | 4 | PCE price, core PCE price, CES payroll, and daily FRBNY EFFR |
| Historical bitemporal target panels | 0 | The 2026-08-02 and 2026-08-04 folders are retrieval snapshots, not historical releases |
| Truth matrices | 0 | First-release, near-mature, and mature layers are missing for every target |
| Approved observation bridges | 0 | Every protocol bridge remains pending validation |
| Resolved artifact-verification receipts | 0 | No local bundle or externally authenticated approval evidence is installed |

The passing `abm_gdp_operator/` suite does not change these counts. It proves
only that the two frozen formulas are applied to each positive finite raw path
with the correct origin/horizon mapping and factor 400. BEA concept
equivalence, historical identities, seasonal adjustment, vintages, truth
layers, and promotion remain unvalidated.

The monthly FRED `FEDFUNDS` series used by the calibration pipeline is not the
required daily Federal Reserve Bank of New York `EFFR` target. The validator
rejects that substitution rather than silently changing the source frequency
or the `quarterly_average_daily` operator.

Every target also pins a machine selector: provider dataset, table ID, line
number where applicable, series code, source unit, and seasonal-adjustment
status. The BEA selectors are `T10106:1/A191RX`, `T20304:1/DPCERG`,
`T20304:25/DPCCRG`, `T10109:1/A191RD`, and `T10105:1/A191RC`.

## Failure semantics

`validate_inventory` rejects malformed or falsely specified contracts:

- any missing, duplicate, renamed, or extra target;
- an unknown field at any schema level;
- any target/source/operator field that differs from the protocol contract;
- weights other than eight `0.125` entries summing to `1.0`;
- invalid calendar dates or unsorted retrieval-date evidence;
- missing or duplicate first-release, near-mature, or mature declarations;
- a monthly `FEDFUNDS` definition for daily EFFR;
- a retrieval-only snapshot labeled as historical bitemporal data;
- an available truth layer with no observations or artifact hash; and
- a stale or incorrect content hash.

An honest unavailable state is valid inventory data. For example,
`status = "missing"` with zero observations records the present absence of a
truth layer. `promotion_readiness` then returns `NOT_READY` with explicit
blockers, and `require_promotion_ready` throws. This preserves the audit fact
without converting missing evidence into a schema error or a passed gate.

Historical coverage requires all of:

```text
installed_status = exact
vintage_status = historical_bitemporal
release_timestamp_status = exact_historical_release_timestamps
historical_vintage_count > 0
```

Retrieval dates alone can only support `current_vintage_only`.

## Truth definitions

Every target requires:

1. `first_release`: the earliest official release reporting the complete
   target reference period;
2. `near_mature`: the third scheduled quarterly estimate for NIPA targets, or
   the latest official monthly/daily vintage at quarter end plus 90 calendar
   days; and
3. `mature`: the latest official vintage at the fixed 60-month lag.

The acquisition route in each target record names the exact-release archive
that must be populated. A future update may mark a layer `available` only with
a positive observation count and a lowercase SHA-256 artifact identifier.
Promotion readiness additionally requires at least 40 observations in every
truth layer and at least 40 historical vintages per target, matching the
protocol's minimum retrospective-origin count.

Those counts and hashes are still declarative inside this inventory. The
separate `../evidence/USEvidenceVerifier.jl` now checks local truth/operator
bytes, target/layer identities, and a common set of 40 origins, but explicitly
reports `verified=false` and `promotion_eligible=false`. It does not resolve
upstream origin bytes, validate horizon/truth-vintage semantics, or
authenticate approvals. The target inventory's integrated promotion resolver
status therefore remains `NOT_IMPLEMENTED_FAIL_CLOSED`. A syntactically
complete inventory returns `EVIDENCE_VERIFICATION_REQUIRED`, never `READY`,
and `require_promotion_ready` throws. A later integration may enable readiness
only after both local integrity and those external semantic/authenticity
checks pass.

## Deterministic identity and use

The content hash uses sorted, typed, length-prefixed canonicalization and
excludes only `artifact.content_sha256`. Dictionary insertion order therefore
does not affect identity; any substantive field change does.

Run the hermetic suite from the repository root:

```sh
julia --startup-file=no \
  scripts/us/forecasting/targets/test_target_coverage.jl
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/targets/abm_gdp_operator/test_abm_gdp_operator_qualification.jl
```

Inspect the checked-in gate:

```sh
julia --startup-file=no -e '
include("scripts/us/forecasting/targets/USTier1TargetCoverage.jl")
using .USTier1TargetCoverage
display(promotion_readiness())
'
```
