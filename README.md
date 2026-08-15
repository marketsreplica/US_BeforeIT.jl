# US BeforeIT

> An independent, U.S.-focused fork of
> [BeforeIT.jl](https://github.com/bancaditalia/BeforeIT.jl), created by
> Banca d'Italia and its contributors.
>
> This fork is maintained by
> [MarketsReplica](https://github.com/MarketsReplica). It is not an official
> Banca d'Italia project and is not endorsed by Banca d'Italia.

US BeforeIT extends the upstream agent-based macroeconomic model with:

- auditable U.S. 2024 Q4 structural and 2026 Q1 nowcast calibrations;
- updated Austrian structural, nowcast, and scenario artifacts;
- reproducible calibration, validation, forecasting, and back-test pipelines;
- a local Simulation Lab and Economy Complexity Explorer.

The initial public branch is based on upstream commit
[`060a206`](https://github.com/bancaditalia/BeforeIT.jl/commit/060a2060e99e106024ce3301c9572cfd44cd9092),
which contains BeforeIT.jl v0.6.0.

## Quick start

Install this fork directly from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/MarketsReplica/US_BeforeIT.jl")
```

Load and run the current U.S. baseline:

```julia
import BeforeIT as Bit

baseline = Bit.load_us_baseline(:nowcast)
model = Bit.Model(baseline.parameters, baseline.initial_conditions)
Bit.run!(model, 20)
```

For development:

```sh
git clone https://github.com/MarketsReplica/US_BeforeIT.jl.git
cd US_BeforeIT.jl
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

Run the web application:

```sh
julia --project=apps/web -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=apps/web apps/web/src/server.jl
```

Then open `http://127.0.0.1:8080`.

See the [U.S. pipeline guide](scripts/us/README.md), the
[web application guide](apps/web/README.md), and
[changes from upstream](CHANGES_FROM_UPSTREAM.md) for details.

## U.S. ABM (BeforeIT-US)

Beyond the calibration artifacts, this fork adds an out-of-sample forecast
evaluation of the agent-based model against ten statistical benchmarks, a
repair of the defect that evaluation exposed, and a re-scoring of the repaired
model on identical cells and seeds. The full write-up is
[US_ABM_FORECAST_REPORT.md](US_ABM_FORECAST_REPORT.md); a Poledna-style paper
version with figures is in [`paper/`](paper/US_ABM_Forecasting_Paper.tex).

**Headline result.** On a matched grid of 61 quarterly origins (2010Q2–2025Q2),
five horizons and 500 paths per origin, the repaired model
`beforeit_abm_us_v2` has the best weighted RMSE ratio of the 14 scored forecast columns
on the headline pair {real GDP growth, GDP-deflator inflation} in all three
sample tracks: **0.830** all-available, **0.829** balanced-h12, **0.796**
pandemic-masked, against a VAR(1) anchor. The pre-repair model scored 0.905,
0.894 and 1.272 — 5th, 5th and 11th of the 14 columns. Real-GDP bias by horizon collapses
from −1.32 / −7.28 / −2.94 / −2.15 / −2.02 pp to −0.03 / −0.10 / −0.14 / −0.12
/ −0.20 pp, the weighted MAE ratio moves from 1.137 to 0.814, and empirical
90 % interval coverage for real GDP moves from 0.654 to 0.929.

**What the repair was.** Two changes in the calibration artifact, not in
behavioural parameters: a biproportional (RAS) reconciliation of the opening
commodity balance on the use side, which clears it to
`max |uses/supply − 1| = 1.0e-13`; and growth expectations re-specified as a
random walk with drift, flag-gated and default-off. Neither repair was
*selected* using forecast errors: each follows from an accounting identity or a
correctly specified estimator. The exercise as a whole remains explicitly
mixed-vintage — 2024 input–output structure and current-vintage data are used at
historical origins — so it does use information unavailable at those origins.

**Labels that must travel with every number above.** This is a **revised-data,
mixed-vintage diagnostic**, not a real-time backtest: `real_time = false`,
`origin_admissible = false`, `promotion_eligible = false`,
`mixed_vintage_structural_year = 2024`. Data are current-vintage throughout,
and the 68×68 input–output structure, firm and employee counts, tax rates and
population are frozen at 2024 and carried back to every historical origin.

**Open defects.** Capital never accumulates (`K24/K0 = 1.0000` measured), so
all of v2's growth drains a fixed 17.6 % opening capacity headroom and
utilisation moves 0.856 → 0.943 over six years; **v2 is validated at h ≤ 12
only and is not a multi-year growth mechanism**. Unemployment collapses to
about 1 % once goods rationing stops, and is excluded from every weighted
score rather than reported as a result.

### Reproduce

The committed ensemble caches are the reproducibility artifact. Each run directory
carries a `cache_identity.toml` that the runner revalidates in full — calibration
artifact, code hashes, panel hashes, path count, seed contract, Julia version —
before it reuses a single cached row, refusing by field name on any mismatch.
Exact regeneration requires **Julia 1.10.3**: seeds derive from `Base.hash` through
the default global RNG, both version-bound, so a cross-version rerun is a new
experiment rather than a reproduction.


```sh
# Hermetic smoke test: builds and steps the ABM from both 2024 artifacts.
julia --project=. -e 'using Pkg; Pkg.test()'

# Rebuild the commodity-balance reconciled calibration artifact (~40 s).
julia --project=scripts/us scripts/us/calibration/reconcile_commodity_balance.jl \
  --mode=final_demand_scaled --expectations=rw_drift

# v1 and v2 ensembles, 61 origins x 500 paths each. Both resume from the
# committed ensemble cache, so a completed run re-scores in seconds.
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v1_headline 500 headline
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline 500 headline_v2 \
  --also-score=output/us_forecasting/abm_v2_comparison/v1_headline

# Score tables.
julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/report_v2_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline \
  output/us_forecasting/abm_v2_comparison_outlook
```

## Origin, citation, and license

The original BeforeIT.jl model and implementation are the work of Aldo
Glielmo, Mitja Devetak, Adriano Meligrana, Sebastian Poledna, and other
upstream contributors. Please cite the original software paper:

```bibtex
@article{glielmo2025beforeit,
  title={BeforeIT.jl: High-Performance Agent-Based Macroeconomics Made Easy},
  author={Glielmo, Aldo and Devetak, Mitja and Meligrana, Adriano and Poledna, Sebastian},
  journal={arXiv preprint arXiv:2502.13267},
  year={2025}
}
```

Source code is distributed under the
[Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution.
Datasets and third-party materials remain subject to their respective source
terms; provenance is recorded in the country pipeline and validation files.
