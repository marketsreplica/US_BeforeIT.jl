# Structural-vintage calibrations (stage-2b workstream 2b-4)

Additional annual structural calibrations of the US BeforeIT model for reference
years **2017** and **2012** (current revised BEA vintage), built alongside the
existing 2024 structure and carried through the identical commodity-balance
reconciliation, per `scripts/us/forecasting/diagnostics/stage2b/STAGE2B_PROTOCOL.md`
("2b-4 structural-vintage robustness").

Nothing here modifies any existing artifact, fixture, raw archive, or script used by
other runs. All outputs are new files.

## Design

Each vintage artifact replicates the schema of the shipped
`data/us/calibration/US_2024_calibration_object.jld2` exactly:

* the **annual/structural row** (the whole `figaro` block from BEA summary supply-use
  tables 259/262; NIPA annual scalars; BEA fixed-asset stocks; QCEW/SUSB/CPS sector
  employment, wages and firm counts; CPS person controls) is rebuilt for the target
  reference year from the same ingestion path as the 2024 structure;
* **every quarterly dynamic series** (`data`, `ea`, and the financial stock series in
  `calibration`) is copied unchanged from the 2024 artifact — the mixed-vintage
  design of the stage-2b program: same quarterly history, different structural year;
* `years_num = [<year>-12-31]`, `max_calibration_date = <year>-12-31`,
  `estimation_date` unchanged (1997-03-31).

The ingestion replication is certified by a **golden test** that rebuilds the 2024
annual structure from the checked-in raw responses (`data/us/raw/...`,
vintage 2026-08-04) and reproduces the shipped artifact **bit-exactly** in every
array, flag, and date.

Documented deviations forced by source-year availability (details in the module
header of `StructuralVintageCalibration.jl`): NAICS-2017/2012 QCEW lists for the
information sectors; same-year SUSB firm counts (no establishment nowcast needed);
QCEW 2012 from the official annual singlefile (the CSV slice API starts 2014);
Census of Agriculture farm counts (2012 and 2017 are census years); no separate
T00OSUB row in the 2017/2012 use tables (netting already inside T00OTOP; identity
verified); published-rounding gates made aggregation/term-count aware exactly per
`USSupplyMakeDiagnostics.published_rounding_tolerance` (the shipped scalar $2m gates
were single-column bounds).

## Usage

```sh
# 1. must pass before anything else is trusted (writes nothing)
julia --project=scripts/us scripts/us/calibration/structural_vintage/build_structural_vintage_calibration.jl --golden-test

# 2. build a vintage structure (fetches + archives sources, writes artifact + provenance TOML)
julia --project=scripts/us scripts/us/calibration/structural_vintage/build_structural_vintage_calibration.jl --year=2017
julia --project=scripts/us scripts/us/calibration/structural_vintage/build_structural_vintage_calibration.jl --year=2012

# 3. identical reconciliation (RAS, final_demand_scaled, rw_drift — the 2024 reconciled configuration)
julia --project=scripts/us scripts/us/calibration/structural_vintage/reconcile_structural_vintage.jl --src=data/us/calibration/US_2017_calibration_object.jld2
julia --project=scripts/us scripts/us/calibration/structural_vintage/reconcile_structural_vintage.jl --src=data/us/calibration/US_2012_calibration_object.jld2

# 4. verification: params + initial conditions at <year>Q4, scale 1e-5, Bit.Model, 4 quarters,
#    no NaN/Inf anywhere, GDP strictly positive
julia --project=scripts/us scripts/us/calibration/structural_vintage/verify_structural_vintage_calibration.jl --artifact=data/us/calibration/US_2017_calibration_object_reconciled.jld2 --year=2017
julia --project=scripts/us scripts/us/calibration/structural_vintage/verify_structural_vintage_calibration.jl --artifact=data/us/calibration/US_2012_calibration_object_reconciled.jld2 --year=2012
```

## Outputs

| file | content |
| --- | --- |
| `data/us/calibration/US_<Y>_calibration_object.jld2` | vintage structure, shipped-2024 schema |
| `data/us/calibration/US_<Y>_calibration_object.provenance.toml` | artifact + input SHA-256s, retrieval times, source URLs |
| `data/us/calibration/US_<Y>_calibration_object_reconciled.jld2` | after the identical RAS reconciliation |
| `data/us/calibration/US_<Y>_calibration_object_reconciled.provenance.toml` | lambda, rho, RAS iterations, residual decomposition |
| `data/us/raw/structural_vintage/...` | archived raw responses (vintage=2026-08-17) |
| `output/us_forecasting/commodity_balance_reconciliation_structural_vintage/US_<Y>_calibration_object/` | full reconciliation report + per-commodity CSV |

Raw responses are archived once and reused on re-runs; existing artifacts are never
overwritten (the builders refuse).
